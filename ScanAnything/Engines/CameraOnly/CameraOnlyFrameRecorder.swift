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
    case progress(
        count: Int,
        featurePointCount: Int,
        viewCoverage: Double,
        message: String
    )
    case failure(String)
}

/// All mutable capture state is serialized on `delegateQueue`.
final class CameraOnlyFrameRecorder: NSObject, ARSessionDelegate, @unchecked Sendable {
    let delegateQueue = DispatchQueue(
        label: "com.nightvibes33.scananything.camera-capture",
        qos: .userInitiated
    )

    private let imagesURL: URL
    private let quality: CameraOnlyQualityProfile
    private let eventHandler: @Sendable (CameraOnlyCaptureEvent) -> Void
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let jpegOptions: [CIImageRepresentationOption: Any] = [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0
    ]

    private var frames: [CameraOnlyFrameMetadata] = []
    private var featurePoints: [SIMD3<Float>] = []
    private var featurePointIdentifiers = Set<UInt64>()
    private var coveredViewBins = Set<Int>()
    private var sharpnessGate: CameraOnlyFrameQualityGate
    private var highResolutionCaptureInFlight = false
    private var lastCapturedTransform: simd_float4x4?
    private var lastCapturedTimestamp: TimeInterval = -1
    private var lastProgressEventTimestamp: TimeInterval = -1
    private var lastProgressMessage = ""

    init(
        imagesURL: URL,
        quality: CameraOnlyQualityProfile,
        eventHandler: @escaping @Sendable (CameraOnlyCaptureEvent) -> Void
    ) {
        self.imagesURL = imagesURL
        self.quality = quality
        self.eventHandler = eventHandler
        self.sharpnessGate = CameraOnlyFrameQualityGate(quality: quality)
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
        consider(frame, session: session)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        eventHandler(.failure(error.localizedDescription))
    }

    private func consider(_ frame: ARFrame, session: ARSession) {
        guard frames.count < quality.maximumFrameCount else { return }

        let trackingMessage: String
        switch frame.camera.trackingState {
        case .normal:
            trackingMessage = guidanceMessage
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

        guard !highResolutionCaptureInFlight else {
            emitProgress(message: trackingMessage, timestamp: frame.timestamp)
            return
        }

        guard shouldCapture(frame) else {
            emitProgress(
                message: trackingMessage,
                timestamp: frame.timestamp
            )
            return
        }

        // Reject motion blur cheaply from the live feed before asking the camera
        // for an expensive full-resolution still.
        let sharpness = SharpnessMeter.scoreFast(frame.capturedImage)
        guard sharpnessGate.accepts(sharpness: sharpness) else {
            emitProgress(
                message: "Hold steadier — blurry view skipped",
                timestamp: frame.timestamp
            )
            return
        }

        highResolutionCaptureInFlight = true
        session.captureHighResolutionFrame { [weak self] capturedFrame, error in
            guard let self else { return }
            self.delegateQueue.async { [weak self] in
                guard let self else { return }
                self.highResolutionCaptureInFlight = false

                if let error {
                    self.emitProgress(
                        message: "High-resolution capture missed — keep moving slowly",
                        timestamp: frame.timestamp,
                        force: true
                    )
                    _ = error
                    return
                }

                guard let capturedFrame else {
                    self.emitProgress(
                        message: "High-resolution capture missed — keep moving slowly",
                        timestamp: frame.timestamp,
                        force: true
                    )
                    return
                }

                self.persist(capturedFrame)
            }
        }
    }

    private func persist(_ frame: ARFrame) {
        guard frames.count < quality.maximumFrameCount else { return }

        guard case .normal = frame.camera.trackingState else {
            emitProgress(
                message: "Tracking changed during capture — view skipped",
                timestamp: frame.timestamp,
                force: true
            )
            return
        }

        let fileName = String(format: "frame_%04d.jpg", frames.count)
        let imageURL = imagesURL.appending(path: fileName, directoryHint: .notDirectory)
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()

        guard let data = imageContext.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: jpegOptions
        ) else {
            eventHandler(.failure("Could not encode this high-resolution camera frame."))
            return
        }

        do {
            try data.write(to: imageURL, options: .atomic)
        } catch {
            eventHandler(.failure(
                "Could not save this camera frame: \(error.localizedDescription)"
            ))
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

        coveredViewBins.insert(viewBin(for: camera.transform))

        // High-resolution ARFrames retain the tracked frame metadata, including
        // raw feature points when ARKit provides them. Stable identifiers are
        // stored only once so the Gaussian seed is not inflated by duplicates.
        if let cloud = frame.rawFeaturePoints,
           featurePoints.count < quality.maximumFeaturePoints {
            for (identifier, point) in zip(cloud.identifiers, cloud.points) {
                guard featurePoints.count < quality.maximumFeaturePoints else { break }
                if featurePointIdentifiers.insert(identifier).inserted {
                    featurePoints.append(point)
                }
            }
        }

        lastCapturedTransform = camera.transform
        lastCapturedTimestamp = frame.timestamp

        emitProgress(
            message: guidanceMessage,
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
            viewCoverage: viewCoverage,
            message: message
        ))
    }

    private var viewCoverage: Double {
        let denominator = quality.azimuthSectorCount * quality.elevationBandCount
        guard denominator > 0 else { return 0 }
        return min(1, Double(coveredViewBins.count) / Double(denominator))
    }

    private var guidanceMessage: String {
        if frames.count >= quality.minimumFrameCount,
           featurePoints.count >= quality.minimumFeaturePoints,
           viewCoverage >= quality.minimumViewCoverage {
            return "Great coverage — you can finish now"
        }

        if frames.count >= quality.minimumFrameCount,
           viewCoverage < quality.minimumViewCoverage {
            return "Change height and fill the missing angles"
        }

        if viewCoverage >= 0.42 {
            return "Make a second pass from a different height"
        }

        return "Orbit slowly around the object"
    }

    private func shouldCapture(_ frame: ARFrame) -> Bool {
        guard frame.timestamp - lastCapturedTimestamp >= quality.minimumCaptureInterval
        else { return false }

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

        // Purely rotating the phone does not add parallax. Require meaningful
        // translation, or at least some translation when rotation is the main
        // source of viewpoint change.
        return translation >= quality.minimumTranslation ||
            (
                translation >= quality.minimumTranslation * 0.45 &&
                rotation >= quality.minimumRotation
            )
    }

    private func viewBin(for transform: simd_float4x4) -> Int {
        let forward = simd_normalize(-SIMD3<Float>(
            transform.columns.2.x,
            transform.columns.2.y,
            transform.columns.2.z
        ))

        let azimuth = atan2(forward.x, -forward.z)
        let normalizedAzimuth = (azimuth + .pi) / (2 * .pi)
        let rawSector = Int(normalizedAzimuth * Float(quality.azimuthSectorCount))
        let sector = min(
            quality.azimuthSectorCount - 1,
            max(0, rawSector)
        )

        let band: Int
        if quality.elevationBandCount <= 1 {
            band = 0
        } else {
            band = forward.y >= 0 ? 1 : 0
        }

        return band * quality.azimuthSectorCount + sector
    }

    private func matrixRows(_ matrix: simd_float4x4) -> [[Double]] {
        (0..<4).map { row in
            (0..<4).map { column in
                Double(matrix[column][row])
            }
        }
    }

    private func limitedTrackingMessage(
        _ reason: ARCamera.TrackingState.Reason
    ) -> String {
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
