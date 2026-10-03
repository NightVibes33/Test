import Foundation

/// One source of truth for the camera-only Gaussian pipeline.
///
/// These values deliberately bias toward reconstruction quality on modern
/// iPhones. Keeping them in a value type makes the capture/reconstruction
/// contract testable and prevents the recorder, UI, and trainer from drifting.
struct CameraOnlyQualityProfile: Sendable, Equatable {
    let targetFrameCount: Int
    let minimumFrameCount: Int
    let maximumFrameCount: Int
    let minimumFeaturePoints: Int
    let minimumCaptureInterval: TimeInterval
    let minimumTranslation: Float
    let minimumRotation: Float

    let trainingIterations: Int32
    let shDegree: Int32
    let shDegreeInterval: Int32
    let numDownscales: Int32
    let resolutionSchedule: Int32
    let warmupLength: Int32
    let refineEvery: Int32
    let stopScreenSizeAt: Int32
    let stopDensifyAt: Int32
    let datasetDownscaleFactor: Float

    static let highDetail = CameraOnlyQualityProfile(
        targetFrameCount: 160,
        minimumFrameCount: 72,
        maximumFrameCount: 240,
        minimumFeaturePoints: 1_000,
        minimumCaptureInterval: 0.15,
        minimumTranslation: 0.018,
        minimumRotation: 0.045,
        trainingIterations: 8_000,
        shDegree: 3,
        shDegreeInterval: 1_000,
        numDownscales: 2,
        resolutionSchedule: 2_500,
        warmupLength: 500,
        refineEvery: 100,
        stopScreenSizeAt: 6_000,
        stopDensifyAt: 5_500,
        datasetDownscaleFactor: 1.0
    )
}
