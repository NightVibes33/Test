import Foundation

/// One source of truth for the camera-only Gaussian pipeline.
///
/// The high-detail profile is tuned around an 8 GB-class modern iPhone such as
/// the iPhone 16. It preserves native 4K source frames, rejects weak inputs, and
/// gives msplat enough full-resolution optimization time to converge instead of
/// stopping shortly after the progressive-resolution warmup.
struct CameraOnlyQualityProfile: Sendable, Equatable {
    let targetFrameCount: Int
    let minimumFrameCount: Int
    let maximumFrameCount: Int
    let minimumFeaturePoints: Int
    let maximumFeaturePoints: Int
    let minimumCaptureInterval: TimeInterval
    let minimumTranslation: Float
    let minimumRotation: Float

    let sharpnessWarmupFrames: Int
    let sharpnessFloorFraction: Float
    let azimuthSectorCount: Int
    let elevationBandCount: Int
    let minimumViewCoverage: Double

    let trainingIterations: Int32
    let shDegree: Int32
    let shDegreeInterval: Int32
    let ssimWeight: Float
    let numDownscales: Int32
    let resolutionSchedule: Int32
    let warmupLength: Int32
    let refineEvery: Int32
    let resetAlphaEvery: Int32
    let densifyGradThresh: Float
    let densifySizeThresh: Float
    let stopScreenSizeAt: Int32
    let stopDensifyAt: Int32
    let splitScreenSize: Float
    let datasetDownscaleFactor: Float

    let learnedDepthPriorEnabled: Bool
    let depthPriorKeyframeCount: Int
    let depthPriorMinimumAnchors: Int
    let depthPriorGridStride: Int
    let depthPriorMaximumPoints: Int
    let depthPriorVoxelSize: Float

    static let highDetail = CameraOnlyQualityProfile(
        targetFrameCount: 220,
        minimumFrameCount: 120,
        maximumFrameCount: 300,
        minimumFeaturePoints: 2_500,
        maximumFeaturePoints: 400_000,
        minimumCaptureInterval: 0.12,
        minimumTranslation: 0.020,
        minimumRotation: 0.050,
        sharpnessWarmupFrames: 8,
        sharpnessFloorFraction: 0.65,
        azimuthSectorCount: 24,
        elevationBandCount: 2,
        minimumViewCoverage: 0.58,
        trainingIterations: 30_000,
        shDegree: 3,
        shDegreeInterval: 1_000,
        ssimWeight: 0.20,
        numDownscales: 3,
        resolutionSchedule: 3_000,
        warmupLength: 750,
        refineEvery: 100,
        resetAlphaEvery: 30,
        densifyGradThresh: 0.00018,
        densifySizeThresh: 0.01,
        stopScreenSizeAt: 12_000,
        stopDensifyAt: 15_000,
        splitScreenSize: 0.045,
        datasetDownscaleFactor: 1.0,
        learnedDepthPriorEnabled: true,
        depthPriorKeyframeCount: 24,
        depthPriorMinimumAnchors: 32,
        depthPriorGridStride: 8,
        depthPriorMaximumPoints: 120_000,
        depthPriorVoxelSize: 0.003
    )
}
