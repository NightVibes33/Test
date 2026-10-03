@preconcurrency import ARKit
import CoreImage
import Foundation
import ImageIO
import simd

struct CameraOnlyFrameMetadata: Sendable {
    let filePath: String
    let width: Int
    let height: Int
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
    let transformMatrix: [[Double]]
}

struct CameraOnlyCaptureSnapshot: Sendable {
    let frames: [CameraOnlyFrameMetadata]
    let featurePoints: [SIMD3<Float>]
}

enum CameraOnlyCaptureEvent: Sendable {
    case progress(count: Int, featurePointCount: Int, message: String)
    case failure(String)
}

final class CameraOnlyFrameRecorder: NSObject, ARSessionDelegate {
    let delegateQueue = DispatchQueue(
        label: "com.nightvibes33.scananything.camera-capture",
        qos: .userInitiated
    )

    private let imagesURL: URL
    private let eventHandler: @Sendable (CameraOnlyCaptureEvent) -> Void
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let jpegOptions: [CIImageRepresentationOption: Any] = [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.98
    ]

    private var frames: [CameraOnlyFrameMetadata] = []
    private var featurePoints: [SIMD3<Float>] = []
    private var featurePointIdentifiers = Set<UInt64>()
    private var lastCapturedTransform: simd_float4x4?
    private var lastCapturedTimestamp: TimeInterval = -1
    private var lastProgressEventTimestamp: TimeInterval = -1
    private var lastProgressMessage = ""

    private let targetFrameCount = 160
    private let maximumFrameCount = 240
    private let maximumFeaturePoints = 250_000

    init(
        imagesURL: URL,
        eventHandler: @escaping @Sendable (CameraOnlyCaptureEvent) -> Void
    ) {
        self.imagesURL = imagesURL
        self.eventHandler = eventHandler
        super.init()
    }

    func snapshot() -> CameraOnlyCaptureSnapshot {
        delegateQueue.sync {
            CameraOnlyCaptureSnapshot(
                frames: frames,
                featurePoints: featurePoints
            )
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        consume(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        eventHandler(.failure(error.localizedDescription))
    }

    private func consume(_ frame: ARFrame) {
        guard frames.count < maximumFrameCount else { return }

        let trackingMessage: String
        switch frame.camera.trackingState {
        case .normal:
            trackingMessage = coverage >= 0.95
                ? "Great coverage — you can finish now"
                : "Move slowly around the object"
        case .limited(let reason):
            emitProgress(
                message: limitedTrackingMessage(reason),
                timestamp: frame.timestamp
            )
            return
        case .notAvailable:
            emitProgress(
                message: "Tracking unavailable",
                timestamp: frame.timestamp
            )
            return
        }

        guard shouldCapture(frame) else {
            emitProgress(
                message: trackingMessage,
                timestamp: frame.timestamp
            )
            return
        }

        let fileName = String(format: "frame_%04d.jpg", frames.count)
        let imageURL = imagesURL.appending(path: fileName, directoryHint: .notDirectory)
        let image = CIImage(cvPixelBuffer: frame.capturedImage)

        guard let data = imageContext.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: jpegOptions
        ) else {
            eventHandler(.failure("Could not encode this camera frame."))
            return
        }

        do {
            try data.write(to: imageURL, options: .atomic)
        } catch {
            eventHandler(.failure("Could not save this camera frame: \(error.localizedDescription)"))
            return
        }

        let camera = frame.camera
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution

        frames.append(
            CameraOnlyFrameMetadata(
                filePath: "images/\(fileName)",
                width: Int(resolution.width),
                height: Int(resolution.height),
                fx: Double(intrinsics[0][0]),
                fy: Double(intrinsics[1][1]),
                cx: Double(intrinsics[2][0]),
                cy: Double(intrinsics[2][1]),
                transformMatrix: matrixRows(camera.transform)
            )
        )

        // ARKit reports many of the same tracked feature points in consecutive
        // frames. Keep each stable identifier only once so the Gaussian seed is
        // real scene geometry instead of tens of thousands of duplicates.
        if let cloud = frame.rawFeaturePoints,
           featurePoints.count < maximumFeaturePoints {
            for (identifier, point) in zip(cloud.identifiers, cloud.points) {
                guard featurePoints.count < maximumFeaturePoints else { break }
                if featurePointIdentifiers.insert(identifier).inserted {
                    featurePoints.append(point)
                }
            }
        }

        lastCapturedTransform = camera.transform
        lastCapturedTimestamp = frame.timestamp

        emitProgress(
            message: coverage >= 0.95
                ? "Great coverage — you can finish now"
                : "Move slowly around the object",
            timestamp: frame.timestamp,
            force: true
        )
    }

    private func emitProgress(
        message: String,
        timestamp: TimeInterval,
        force: Bool = false
    ) {
        let messageChanged = message != lastProgressMessage
        let enoughTimePassed = timestamp - lastProgressEventTimestamp >= 0.20

        guard force || messageChanged || enoughTimePassed else { return }

        lastProgressMessage = message
        lastProgressEventTimestamp = timestamp
        eventHandler(.progress(
            count: frames.count,
            featurePointCount: featurePoints.count,
            message: message
        ))
    }

    private var coverage: Double {
        min(1, Double(frames.count) / Double(targetFrameCount))
    }

    private func shouldCapture(_ frame: ARFrame) -> Bool {
        guard frame.timestamp - lastCapturedTimestamp >= 0.15 else { return false }
        guard let previous = lastCapturedTransform else { return true }

        let current = frame.camera.transform
        let a = SIMD3<Float>(
            previous.columns.3.x,
            previous.columns.3.y,
            previous.columns.3.z
        )
        let b = SIMD3<Float>(
            current.columns.3.x,
            current.columns.3.y,
            current.columns.3.z
        )
        let translation = simd_distance(a, b)

        let previousForward = simd_normalize(-SIMD3<Float>(
            previous.columns.2.x,
            previous.columns.2.y,
            previous.columns.2.z
        ))
        let currentForward = simd_normalize(-SIMD3<Float>(
            current.columns.2.x,
            current.columns.2.y,
            current.columns.2.z
        ))
        let dotValue = simd_dot(previousForward, currentForward)
        let clamped = max(-1 as Float, min(1 as Float, dotValue))
        let rotation = acos(clamped)

        // Tighter pose spacing gives the trainer substantially more overlap,
        // which matters much more at 4K than simply collecting a few wide views.
        return translation >= 0.018 || rotation >= 0.045
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
