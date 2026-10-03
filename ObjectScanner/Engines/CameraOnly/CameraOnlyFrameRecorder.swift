import ARKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import simd

enum CameraOnlyCaptureEvent: Sendable {
    case captured(frameCount: Int, featurePointCount: Int)
    case tracking(message: String?)
    case failed(message: String)
}

final class CameraOnlyFrameRecorder: NSObject, ARSessionDelegate {
    let delegateQueue = DispatchQueue(label: "com.nightvibes33.scananything.camera-recorder", qos: .userInitiated)

    private let imagesURL: URL
    private let onEvent: @Sendable (CameraOnlyCaptureEvent) -> Void
    private let context = CIContext(options: [.cacheIntermediates: false])

    private var frames: [CameraOnlyFrame] = []
    private var featurePoints: [SIMD3<Float>] = []
    private var lastTransform: simd_float4x4?
    private var lastCaptureTime: TimeInterval = 0
    private let maxFeaturePoints = 25_000
    private let maxFrames = 100

    init(imagesURL: URL, onEvent: @escaping @Sendable (CameraOnlyCaptureEvent) -> Void) {
        self.imagesURL = imagesURL
        self.onEvent = onEvent
        super.init()
    }

    func snapshot() -> CameraOnlyRecorderSnapshot {
        delegateQueue.sync {
            CameraOnlyRecorderSnapshot(frames: frames, featurePoints: featurePoints)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else {
            onEvent(.tracking(message: trackingMessage(frame.camera.trackingState)))
            return
        }

        onEvent(.tracking(message: nil))
        guard frames.count < maxFrames else { return }
        guard shouldCapture(frame) else { return }

        do {
            try capture(frame)
        } catch {
            onEvent(.failed(message: error.localizedDescription))
        }
    }

    private func shouldCapture(_ frame: ARFrame) -> Bool {
        if frames.isEmpty { return true }
        guard frame.timestamp - lastCaptureTime >= 0.16, let lastTransform else { return false }

        let a = lastTransform.columns.3
        let b = frame.camera.transform.columns.3
        let distance = simd_distance(SIMD3(a.x, a.y, a.z), SIMD3(b.x, b.y, b.z))

        let lastForward = simd_normalize(-SIMD3(lastTransform.columns.2.x, lastTransform.columns.2.y, lastTransform.columns.2.z))
        let forward = simd_normalize(-SIMD3(frame.camera.transform.columns.2.x, frame.camera.transform.columns.2.y, frame.camera.transform.columns.2.z))
        let dotValue = min(max(simd_dot(lastForward, forward), -1), 1)
        let angle = acos(dotValue)

        return distance >= 0.035 || angle >= 0.07
    }

    private func capture(_ frame: ARFrame) throws {
        let number = frames.count + 1
        let fileName = String(format: "frame-%04d.jpg", number)
        let destinationURL = imagesURL.appending(path: fileName)
        let image = CIImage(cvPixelBuffer: frame.capturedImage)

        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try (output as Data).write(to: destinationURL, options: .atomic)

        let camera = frame.camera
        frames.append(
            CameraOnlyFrame(
                fileName: fileName,
                cameraToWorld: flatten(camera.transform),
                intrinsics: flatten(camera.intrinsics),
                width: Int(camera.imageResolution.width),
                height: Int(camera.imageResolution.height)
            )
        )

        if let cloud = frame.rawFeaturePoints, featurePoints.count < maxFeaturePoints {
            let remaining = maxFeaturePoints - featurePoints.count
            let strideBy = max(1, cloud.points.count / min(max(remaining, 1), 600))
            var index = 0
            while index < cloud.points.count && featurePoints.count < maxFeaturePoints {
                featurePoints.append(cloud.points[index])
                index += strideBy
            }
        }

        lastTransform = camera.transform
        lastCaptureTime = frame.timestamp
        onEvent(.captured(frameCount: frames.count, featurePointCount: featurePoints.count))
    }

    private func flatten(_ matrix: simd_float4x4) -> [Float] {
        let c = matrix.columns
        return [
            c.0.x, c.0.y, c.0.z, c.0.w,
            c.1.x, c.1.y, c.1.z, c.1.w,
            c.2.x, c.2.y, c.2.z, c.2.w,
            c.3.x, c.3.y, c.3.z, c.3.w
        ]
    }

    private func flatten(_ matrix: simd_float3x3) -> [Float] {
        let c = matrix.columns
        return [
            c.0.x, c.0.y, c.0.z,
            c.1.x, c.1.y, c.1.z,
            c.2.x, c.2.y, c.2.z
        ]
    }

    private func trackingMessage(_ state: ARCamera.TrackingState) -> String? {
        switch state {
        case .normal:
            nil
        case .notAvailable:
            "Camera tracking is unavailable."
        case .limited(let reason):
            switch reason {
            case .initializing: "Initializing tracking…"
            case .excessiveMotion: "Move the iPhone more slowly."
            case .insufficientFeatures: "Aim at a more textured area around the object."
            case .relocalizing: "Relocalizing…"
            @unknown default: "Tracking is limited."
            }
        }
    }
}
