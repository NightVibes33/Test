@preconcurrency import ARKit
import CoreImage
import CoreVideo
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

struct CameraOnlyFeaturePoint: Sendable {
    let position: SIMD3<Float>
    let color: SIMD3<UInt8>
}

struct CameraOnlyCaptureSnapshot: Sendable {
    let frames: [CameraOnlyFrameMetadata]
    let featurePoints: [CameraOnlyFeaturePoint]
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
    private let purpose: CameraOnlyCapturePurpose
    private let eventHandler: @Sendable (CameraOnlyCaptureEvent) -> Void
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let jpegOptions: [CIImageRepresentationOption: Any] = [
        kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0
    ]

    private var frames: [CameraOnlyFrameMetadata] = []
    private var featurePoints: [CameraOnlyFeaturePoint] = []
    private var featurePointIdentifiers = Set<UInt64>()
    private var depthVoxels = Set<DepthVoxelKey>()
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
        purpose: CameraOnlyCapturePurpose,
        eventHandler: @escaping @Sendable (CameraOnlyCaptureEvent) -> Void
    ) {
        self.imagesURL = imagesURL
        self.quality = quality
        self.purpose = purpose
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
        if frames.count >= purpose.maximumFrameCount, captureReady {
            return
        }

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

        let fallbackFeaturePoints = frame.rawFeaturePoints?.points ?? []
        let fallbackFeatureIdentifiers = frame.rawFeaturePoints?.identifiers ?? []
        let hardwareDepthPoints = sceneDepthPoints(from: frame)

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

                self.persist(
                    capturedFrame,
                    fallbackFeaturePoints: fallbackFeaturePoints,
                    fallbackFeatureIdentifiers: fallbackFeatureIdentifiers,
                    hardwareDepthPoints: hardwareDepthPoints
                )
            }
        }
    }

    private func persist(
        _ frame: ARFrame,
        fallbackFeaturePoints: [SIMD3<Float>],
        fallbackFeatureIdentifiers: [UInt64],
        hardwareDepthPoints: [CameraOnlyFeaturePoint]
    ) {
        guard frames.count < quality.maximumFrameCount else { return }
        if frames.count >= purpose.maximumFrameCount, captureReady {
            return
        }

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
        let intrinsics = scaledIntrinsics(
            camera: camera,
            pixelBuffer: frame.capturedImage
        )
        let width = CVPixelBufferGetWidth(frame.capturedImage)
        let height = CVPixelBufferGetHeight(frame.capturedImage)

        frames.append(
            CameraOnlyFrameMetadata(
                filePath: "images/\(fileName)",
                width: width,
                height: height,
                fx: Double(intrinsics.fx),
                fy: Double(intrinsics.fy),
                cx: Double(intrinsics.cx),
                cy: Double(intrinsics.cy),
                transformMatrix: matrixRows(camera.transform)
            )
        )

        coveredViewBins.insert(viewBin(for: camera.transform))

        // Metric LiDAR samples take priority when available. They use the same
        // world coordinate system as ARKit poses and therefore improve geometry
        // without changing the user-facing scan mode.
        appendHardwareDepthPoints(hardwareDepthPoints)

        // Seed every Gaussian with the real camera color at the tracked 3D
        // feature. msplat otherwise falls back to flat 50% gray for XYZ-only
        // PLY input, which makes the optimizer spend early iterations learning
        // base color that ARKit already observed.
        if featurePoints.count < quality.maximumFeaturePoints {
            if let cloud = frame.rawFeaturePoints {
                appendFeaturePoints(
                    points: cloud.points,
                    identifiers: cloud.identifiers,
                    camera: camera,
                    pixelBuffer: frame.capturedImage
                )
            } else if !fallbackFeaturePoints.isEmpty {
                appendFeaturePoints(
                    points: fallbackFeaturePoints,
                    identifiers: fallbackFeatureIdentifiers,
                    camera: camera,
                    pixelBuffer: frame.capturedImage
                )
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

    private struct DepthVoxelKey: Hashable {
        let x: Int
        let y: Int
        let z: Int

        init(_ point: SIMD3<Float>, size: Float = 0.004) {
            let voxel = max(size, 0.001)
            x = Int(floor(point.x / voxel))
            y = Int(floor(point.y / voxel))
            z = Int(floor(point.z / voxel))
        }
    }

    /// Converts ARKit LiDAR scene depth into colored world-space Gaussian seeds.
    ///
    /// This path is simply absent on devices without scene depth, so it improves
    /// Pro hardware without making Pro hardware a prerequisite.
    private func sceneDepthPoints(
        from frame: ARFrame
    ) -> [CameraOnlyFeaturePoint] {
        guard let sceneDepth = frame.sceneDepth else { return [] }

        let depthMap = sceneDepth.depthMap
        let format = CVPixelBufferGetPixelFormatType(depthMap)
        guard format == kCVPixelFormatType_DepthFloat32 ||
              format == kCVPixelFormatType_OneComponent32Float
        else {
            return []
        }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        guard depthWidth > 0, depthHeight > 0 else { return [] }

        let camera = frame.camera
        let resolution = camera.imageResolution
        let sourceWidth = max(Float(resolution.width), 1)
        let sourceHeight = max(Float(resolution.height), 1)
        let scaleX = Float(depthWidth) / sourceWidth
        let scaleY = Float(depthHeight) / sourceHeight
        let intrinsics = camera.intrinsics
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY
        guard fx > 0, fy > 0 else { return [] }

        let image = frame.capturedImage
        let imageWidth = CVPixelBufferGetWidth(image)
        let imageHeight = CVPixelBufferGetHeight(image)
        let confidence = sceneDepth.confidenceMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        if let confidence {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
        }
        defer {
            if let confidence {
                CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
            }
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else {
            return []
        }
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        let confidenceBase = confidence.flatMap {
            CVPixelBufferGetBaseAddress($0)
        }
        let confidenceBytesPerRow = confidence.map {
            CVPixelBufferGetBytesPerRow($0)
        } ?? 0

        let maxDepth: Float
        switch purpose {
        case .object, .product:
            maxDepth = 3.0
        case .room, .freeform:
            maxDepth = 10.0
        }

        let maxPerFrame = min(
            5_000,
            max(
                1_500,
                quality.maximumFeaturePoints /
                max(quality.targetFrameCount * 2, 1)
            )
        )
        let stride = 3
        var output: [CameraOnlyFeaturePoint] = []
        output.reserveCapacity(maxPerFrame)

        for y in Swift.stride(from: 0, to: depthHeight, by: stride) {
            if output.count >= maxPerFrame { break }

            let depthRow = depthBase
                .advanced(by: y * depthBytesPerRow)

            for x in Swift.stride(from: 0, to: depthWidth, by: stride) {
                if output.count >= maxPerFrame { break }

                if let confidenceBase {
                    let confidenceRow = confidenceBase
                        .advanced(by: y * confidenceBytesPerRow)
                        .assumingMemoryBound(to: UInt8.self)
                    // 0 = low, 1 = medium, 2 = high. Reject only low-confidence
                    // LiDAR samples; medium/high carry useful metric geometry.
                    guard confidenceRow[x] >= 1 else { continue }
                }

                let depth = depthRow.loadUnaligned(
                    fromByteOffset: x * MemoryLayout<Float>.size,
                    as: Float.self
                )
                guard depth.isFinite,
                      depth >= 0.08,
                      depth <= maxDepth
                else {
                    continue
                }

                let u = Float(x) + 0.5
                let v = Float(y) + 0.5
                let cameraX = (u - cx) / fx * depth
                let cameraY = -(v - cy) / fy * depth
                let cameraPoint = SIMD4<Float>(
                    cameraX,
                    cameraY,
                    -depth,
                    1
                )
                let world4 = camera.transform * cameraPoint
                let world = SIMD3<Float>(world4.x, world4.y, world4.z)

                let imageX = min(
                    imageWidth - 1,
                    max(0, Int(u / Float(depthWidth) * Float(imageWidth)))
                )
                let imageY = min(
                    imageHeight - 1,
                    max(0, Int(v / Float(depthHeight) * Float(imageHeight)))
                )
                let color = sampleColor(
                    image,
                    x: imageX,
                    y: imageY
                ) ?? SIMD3<UInt8>(repeating: 128)

                output.append(
                    CameraOnlyFeaturePoint(
                        position: world,
                        color: color
                    )
                )
            }
        }

        return output
    }

    private func appendHardwareDepthPoints(
        _ points: [CameraOnlyFeaturePoint]
    ) {
        for point in points {
            guard featurePoints.count < quality.maximumFeaturePoints else {
                return
            }

            let voxel = DepthVoxelKey(point.position)
            guard depthVoxels.insert(voxel).inserted else { continue }
            featurePoints.append(point)
        }
    }

    private func appendFeaturePoints(
        points: [SIMD3<Float>],
        identifiers: [UInt64],
        camera: ARCamera,
        pixelBuffer: CVPixelBuffer
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let worldToCamera = camera.transform.inverse
        let intrinsics = scaledIntrinsics(
            camera: camera,
            pixelBuffer: pixelBuffer
        )
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        for (identifier, point) in zip(identifiers, points) {
            guard featurePoints.count < quality.maximumFeaturePoints else { break }
            guard !featurePointIdentifiers.contains(identifier) else { continue }

            let cameraPoint = worldToCamera * SIMD4<Float>(
                point.x,
                point.y,
                point.z,
                1
            )
            let depth = -cameraPoint.z
            guard depth > 0.02 else { continue }

            let u = intrinsics.fx * cameraPoint.x / depth + intrinsics.cx
            let v = intrinsics.cy - intrinsics.fy * cameraPoint.y / depth
            guard u.isFinite, v.isFinite else { continue }

            let x = Int(u.rounded())
            let y = Int(v.rounded())
            guard x >= 0, x < width, y >= 0, y < height else { continue }

            let color = sampleColor(
                pixelBuffer,
                x: x,
                y: y
            ) ?? SIMD3<UInt8>(repeating: 128)

            featurePointIdentifiers.insert(identifier)
            featurePoints.append(
                CameraOnlyFeaturePoint(
                    position: point,
                    color: color
                )
            )
        }
    }

    private func scaledIntrinsics(
        camera: ARCamera,
        pixelBuffer: CVPixelBuffer
    ) -> (fx: Float, fy: Float, cx: Float, cy: Float) {
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution
        let width = Float(CVPixelBufferGetWidth(pixelBuffer))
        let height = Float(CVPixelBufferGetHeight(pixelBuffer))

        let sourceWidth = max(Float(resolution.width), 1)
        let sourceHeight = max(Float(resolution.height), 1)
        let scaleX = width / sourceWidth
        let scaleY = height / sourceHeight

        return (
            fx: intrinsics[0][0] * scaleX,
            fy: intrinsics[1][1] * scaleY,
            cx: intrinsics[2][0] * scaleX,
            cy: intrinsics[2][1] * scaleY
        )
    }

    private func sampleColor(
        _ pixelBuffer: CVPixelBuffer,
        x: Int,
        y: Int
    ) -> SIMD3<UInt8>? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
                  let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                  let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
            else { return nil }

            let lumaRow = yBase
                .advanced(by: y * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
                .assumingMemoryBound(to: UInt8.self)

            let chromaX = x / 2
            let chromaY = y / 2
            let chromaRow = cbcrBase
                .advanced(by: chromaY * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))
                .assumingMemoryBound(to: UInt8.self)

            let yPrime = Float(lumaRow[x]) / 255
            let cb = Float(chromaRow[chromaX * 2]) / 255
            let cr = Float(chromaRow[chromaX * 2 + 1]) / 255

            // ARKit capturedImage is full-range Y'CbCr. These coefficients are
            // Apple's documented T.871 conversion used by its Metal AR sample.
            let red = yPrime + 1.4020 * cr - 0.7010
            let green = yPrime - 0.3441 * cb - 0.7141 * cr + 0.5291
            let blue = yPrime + 1.7720 * cb - 0.8860

            return SIMD3(
                colorByte(red),
                colorByte(green),
                colorByte(blue)
            )

        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let row = base
                .advanced(by: y * CVPixelBufferGetBytesPerRow(pixelBuffer))
                .assumingMemoryBound(to: UInt8.self)
            let offset = x * 4
            return SIMD3(row[offset + 2], row[offset + 1], row[offset])

        default:
            return nil
        }
    }

    private func colorByte(_ value: Float) -> UInt8 {
        let clamped = min(max(value, 0), 1)
        return UInt8(clamping: Int((clamped * 255).rounded()))
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

    private var captureReady: Bool {
        let requiredFrames = max(
            quality.minimumFrameCount,
            purpose.minimumFrameCount
        )
        let requiredCoverage = max(
            quality.minimumViewCoverage,
            purpose.minimumViewCoverage
        )

        return frames.count >= requiredFrames &&
            featurePoints.count >= quality.minimumFeaturePoints &&
            viewCoverage >= requiredCoverage
    }

    private var guidanceMessage: String {
        let requiredFrames = max(quality.minimumFrameCount, purpose.minimumFrameCount)
        let requiredCoverage = max(quality.minimumViewCoverage, purpose.minimumViewCoverage)

        if captureReady {
            return "Great coverage — you can finish now"
        }

        switch purpose {
        case .object:
            if frames.count >= requiredFrames {
                return "Fill the missing sides and add a slightly higher or lower view"
            }
            return "Move around the object — aim for 8–20 clear views"
        case .room:
            if viewCoverage >= requiredCoverage * 0.75 {
                return "Cover the remaining walls, corners and floor"
            }
            return "Walk slowly through the room and point at each side"
        case .product:
            if frames.count >= requiredFrames {
                return "Capture the top, bottom and any missing side"
            }
            return "Keep the item centered and capture every side"
        case .freeform:
            if viewCoverage >= requiredCoverage * 0.75 {
                return "Fill the remaining angles"
            }
            return "Move through the scene and overlap each new view"
        }
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
