@preconcurrency import ARKit
import CoreImage
import Foundation
import Observation
import simd

@MainActor
@Observable
final class CameraOnlyCaptureEngine: NSObject {
    enum Phase: Equatable {
        case idle
        case capturing
        case reconstructing
        case done(ScanRecord)
        case failed(String)
        case cancelled
    }

    let session = ARSession()

    private let storage: ScanStorage
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var workspace: ScanWorkspace?
    private var frames: [[String: Any]] = []
    private var featurePoints: [SIMD3<Float>] = []
    private var lastCapturedTransform: simd_float4x4?
    private var lastCapturedTimestamp: TimeInterval = -1

    private let targetFrameCount = 80
    private let maximumFrameCount = 140

    private(set) var phase: Phase = .idle
    private(set) var capturedCount = 0
    private(set) var trackingMessage = "Move slowly around the object"
    private(set) var processingProgress = 0.0
    private(set) var gaussianCount = 0

    var coverage: Double {
        min(1, Double(capturedCount) / Double(targetFrameCount))
    }

    var canFinish: Bool {
        capturedCount >= 24 && featurePoints.count >= 100
    }

    init(storage: ScanStorage) {
        self.storage = storage
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func start() throws {
        guard ARWorldTrackingConfiguration.isSupported else {
            throw ScanEngineError.sessionUnavailable("AR world tracking is not supported on this device.")
        }

        workspace = try storage.makeWorkspace()
        frames.removeAll(keepingCapacity: true)
        featurePoints.removeAll(keepingCapacity: true)
        capturedCount = 0
        processingProgress = 0
        gaussianCount = 0
        lastCapturedTransform = nil
        lastCapturedTimestamp = -1

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true
        configuration.environmentTexturing = .none

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        phase = .capturing
    }

    func finish() {
        guard case .capturing = phase, let workspace else { return }
        guard canFinish else {
            phase = .failed("Keep scanning. Capture at least 24 well-tracked views around the object.")
            return
        }

        session.pause()
        phase = .reconstructing
        processingProgress = 0

        do {
            try writeDataset(in: workspace)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        let count = capturedCount
        let outputURL = workspace.root.appending(path: "model.spz", directoryHint: .notDirectory)

        Task {
            do {
                let splats = try await GaussianReconstructor.reconstruct(
                    datasetRoot: workspace.root,
                    outputURL: outputURL
                ) { [weak self] progress, splatCount in
                    self?.processingProgress = progress
                    self?.gaussianCount = splatCount
                }

                let record = ScanRecord(
                    id: workspace.id,
                    name: "3D Scan",
                    engine: .objectCapture,
                    modelFileName: "model.spz",
                    isMetricallyScaled: false,
                    imageCount: count,
                    pointCount: splats,
                    detail: nil,
                    summary: "Camera 3D"
                )
                storage.commit(record, workspace: workspace)
                phase = .done(record)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        session.pause()
        if let workspace {
            storage.discard(workspace)
        }
        phase = .cancelled
    }

    private func consume(_ frame: ARFrame) {
        guard case .capturing = phase,
              capturedCount < maximumFrameCount,
              let workspace
        else { return }

        switch frame.camera.trackingState {
        case .normal:
            trackingMessage = coverage >= 0.95
                ? "Great coverage — you can finish now"
                : "Move slowly around the object"
        case .limited(let reason):
            trackingMessage = limitedTrackingMessage(reason)
            return
        case .notAvailable:
            trackingMessage = "Tracking unavailable"
            return
        }

        guard shouldCapture(frame) else { return }

        let fileName = String(format: "frame_%04d.jpg", capturedCount)
        let imageURL = workspace.imagesURL.appending(path: fileName, directoryHint: .notDirectory)
        let image = CIImage(cvPixelBuffer: frame.capturedImage)

        guard let data = imageContext.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [:]
        ) else { return }

        do {
            try data.write(to: imageURL, options: .atomic)
        } catch {
            trackingMessage = "Could not save this camera frame"
            return
        }

        let camera = frame.camera
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution

        frames.append([
            "file_path": "images/\(fileName)",
            "w": Int(resolution.width),
            "h": Int(resolution.height),
            "fl_x": Double(intrinsics[0][0]),
            "fl_y": Double(intrinsics[1][1]),
            "cx": Double(intrinsics[2][0]),
            "cy": Double(intrinsics[2][1]),
            "camera_model": "OPENCV",
            "k1": 0.0,
            "k2": 0.0,
            "p1": 0.0,
            "p2": 0.0,
            "transform_matrix": matrixRows(camera.transform)
        ])

        if let cloud = frame.rawFeaturePoints {
            let room = max(0, 100_000 - featurePoints.count)
            if room > 0 {
                featurePoints.append(contentsOf: cloud.points.prefix(room))
            }
        }

        capturedCount += 1
        lastCapturedTransform = camera.transform
        lastCapturedTimestamp = frame.timestamp
    }

    private func shouldCapture(_ frame: ARFrame) -> Bool {
        guard frame.timestamp - lastCapturedTimestamp >= 0.20 else { return false }
        guard let previous = lastCapturedTransform else { return true }

        let current = frame.camera.transform
        let a = SIMD3<Float>(previous.columns.3.x, previous.columns.3.y, previous.columns.3.z)
        let b = SIMD3<Float>(current.columns.3.x, current.columns.3.y, current.columns.3.z)
        let translation = simd_distance(a, b)

        let previousForward = simd_normalize(-SIMD3<Float>(
            previous.columns.2.x, previous.columns.2.y, previous.columns.2.z
        ))
        let currentForward = simd_normalize(-SIMD3<Float>(
            current.columns.2.x, current.columns.2.y, current.columns.2.z
        ))
        let dotValue = simd_dot(previousForward, currentForward)
        let clamped = max(-1 as Float, min(1 as Float, dotValue))
        let rotation = acos(clamped)

        return translation >= 0.025 || rotation >= 0.07
    }

    private func writeDataset(in workspace: ScanWorkspace) throws {
        guard !frames.isEmpty else { throw ScanEngineError.noImagesCaptured }
        guard featurePoints.count >= 100 else {
            throw ScanEngineError.reconstructionFailed(
                "ARKit did not collect enough stable feature points. Use a textured surface and brighter light."
            )
        }

        let json: [String: Any] = [
            "camera_model": "OPENCV",
            "frames": frames,
            "ply_file_path": "points3D.ply"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(
            to: workspace.root.appending(path: "transforms.json", directoryHint: .notDirectory),
            options: .atomic
        )

        try PointCloudFile.write(
            points: featurePoints,
            to: workspace.root.appending(path: "points3D.ply", directoryHint: .notDirectory)
        )
    }

    private func matrixRows(_ matrix: simd_float4x4) -> [[Double]] {
        (0..<4).map { row in
            (0..<4).map { column in
                Double(matrix[column][row])
            }
        }
    }

    private func limitedTrackingMessage(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing:
            "Initializing tracking…"
        case .excessiveMotion:
            "Slow down"
        case .insufficientFeatures:
            "Aim at a more textured area"
        case .relocalizing:
            "Recovering tracking…"
        @unknown default:
            "Tracking limited"
        }
    }
}

extension CameraOnlyCaptureEngine: @preconcurrency ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        consume(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        phase = .failed(error.localizedDescription)
    }
}
