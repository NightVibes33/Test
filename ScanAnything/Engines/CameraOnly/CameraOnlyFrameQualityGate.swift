import Foundation

/// Rejects relatively soft camera frames after a short calibration window.
///
/// Sharpness is intentionally relative to this scan instead of using one global
/// threshold: a detailed outdoor scene and a low-texture indoor wall naturally
/// produce very different gradient-energy scores.
struct CameraOnlyFrameQualityGate: Sendable {
    private let warmupFrameCount: Int
    private let sharpnessFloorFraction: Float
    private var acceptedSharpness: [Float] = []

    init(quality: CameraOnlyQualityProfile) {
        warmupFrameCount = quality.sharpnessWarmupFrames
        sharpnessFloorFraction = quality.sharpnessFloorFraction
    }

    mutating func accepts(sharpness: Float?) -> Bool {
        guard let sharpness,
              sharpness.isFinite,
              sharpness > 0
        else {
            // If the pixel format cannot be scored, keep the frame rather than
            // throwing away otherwise valid geometry.
            return true
        }

        if acceptedSharpness.count < warmupFrameCount {
            record(sharpness)
            return true
        }

        let sorted = acceptedSharpness.sorted()
        let reference = sorted[sorted.count / 2]
        guard sharpness >= reference * sharpnessFloorFraction else {
            return false
        }

        record(sharpness)
        return true
    }

    private mutating func record(_ sharpness: Float) {
        acceptedSharpness.append(sharpness)

        // A short rolling window adapts to lighting/texture changes while still
        // rejecting sudden motion blur.
        if acceptedSharpness.count > 12 {
            acceptedSharpness.removeFirst(acceptedSharpness.count - 12)
        }
    }
}
