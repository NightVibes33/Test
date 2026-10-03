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

    // iPhone stability controls. These do not lower source capture resolution or
    // the 30K optimization budget; they bound transient memory/GPU backlog.
    let imageCacheMB: Int
    let gpuSyncInterval: Int
    let memorySafetyHeadroomMB: Int
    let minimumEmergencyFinalizeIteration: Int
    let seriousThermalPauseMilliseconds: Int
    let criticalThermalPauseMilliseconds: Int

    let learnedDepthPriorEnabled: Bool
    let depthPriorKeyframeCount: Int
    let depthPriorMinimumAnchors: Int
    let depthPriorGridStride: Int
    let depthPriorMaximumPoints: Int
    let depthPriorVoxelSize: Float

    static let highDetail = CameraOnlyQualityProfile(
        targetFrameCount: 16,
        minimumFrameCount: 8,
        maximumFrameCount: 120,
        minimumFeaturePoints: 500,
        maximumFeaturePoints: 120_000,
        minimumCaptureInterval: 0.12,
        minimumTranslation: 0.020,
        minimumRotation: 0.050,
        sharpnessWarmupFrames: 8,
        sharpnessFloorFraction: 0.65,
        azimuthSectorCount: 12,
        elevationBandCount: 2,
        minimumViewCoverage: 0.25,
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
        // Learned depth already gives the model a dense seed. Stop population
        // growth sooner, then spend the rest of the 30K budget refining the
        // existing splats at full resolution instead of ballooning memory.
        stopDensifyAt: 12_000,
        splitScreenSize: 0.045,
        datasetDownscaleFactor: 1.0,
        imageCacheMB: 256,
        gpuSyncInterval: 50,
        memorySafetyHeadroomMB: 320,
        minimumEmergencyFinalizeIteration: 18_000,
        seriousThermalPauseMilliseconds: 200,
        criticalThermalPauseMilliseconds: 1_000,
        learnedDepthPriorEnabled: true,
        depthPriorKeyframeCount: 24,
        depthPriorMinimumAnchors: 32,
        depthPriorGridStride: 8,
        depthPriorMaximumPoints: 120_000,
        depthPriorVoxelSize: 0.003
    )
}
