import Testing
@testable import ScanAnything

@Suite("ScanAnything core behavior")
struct ScanAnythingCoreTests {
    @Test("Camera-only is a visual splat pipeline, not a mesh pipeline")
    func cameraOnlyEngineProperties() {
        #expect(ScanEngineKind.cameraOnly.producesMesh == false)
        #expect(ScanEngineKind.cameraOnly.displayName == "Camera 3D")
    }

    @Test("Regular iPhones fall back to Camera 3D")
    func cameraOnlyRecommendation() {
        let profile = ObjectProfile(
            size: .small,
            finish: .matte,
            pattern: .rich
        )

        let recommendation = profile.recommendation(
            availableKinds: [.cameraOnly]
        )

        #expect(recommendation.kind == .cameraOnly)
    }

    @Test("SPZ scan records are identified as Gaussian splats")
    func gaussianRecordDetection() {
        let record = ScanRecord(
            name: "Camera scan",
            engine: .cameraOnly,
            modelFileName: "model.spz",
            isMetricallyScaled: false
        )

        #expect(record.isGaussianSplat)
        #expect(record.isPreviewable == false)
    }

    @Test("USDZ scan records remain RealityKit-previewable meshes")
    func usdzRecordDetection() {
        let record = ScanRecord(
            name: "LiDAR scan",
            engine: .objectCapture,
            modelFileName: "model.usdz",
            isMetricallyScaled: true
        )

        #expect(record.isGaussianSplat == false)
        #expect(record.isPreviewable)
        #expect(record.engine.producesMesh)
    }

    @Test("High-detail Camera 3D preserves 4K input and uses a full msplat quality budget")
    func highDetailCameraQualityProfile() {
        let quality = CameraOnlyQualityProfile.highDetail

        #expect(quality.datasetDownscaleFactor == 1.0)
        #expect(quality.targetFrameCount >= 200)
        #expect(quality.minimumFrameCount >= 100)
        #expect(quality.maximumFrameCount >= quality.targetFrameCount)
        #expect(quality.minimumFeaturePoints >= 2_000)
        #expect(quality.maximumFeaturePoints >= 250_000)

        #expect(quality.sharpnessWarmupFrames >= 6)
        #expect(quality.sharpnessFloorFraction >= 0.60)
        #expect(quality.minimumViewCoverage > 0.50)

        #expect(quality.trainingIterations == 30_000)
        #expect(quality.shDegree == 3)
        #expect(quality.ssimWeight == 0.20)
        #expect(quality.numDownscales == 3)
        #expect(quality.stopDensifyAt >= 15_000)
        #expect(
            quality.resolutionSchedule * quality.numDownscales <
            quality.stopDensifyAt
        )
        #expect(quality.stopDensifyAt < quality.trainingIterations)
    }

    @Test("Camera-only blur gate rejects a soft outlier after calibration")
    func cameraOnlyBlurGateRejectsSoftOutlier() {
        let quality = CameraOnlyQualityProfile.highDetail
        var gate = CameraOnlyFrameQualityGate(quality: quality)

        for _ in 0..<quality.sharpnessWarmupFrames {
            #expect(gate.accepts(sharpness: 100))
        }

        #expect(gate.accepts(sharpness: 80))
        #expect(gate.accepts(sharpness: 30) == false)
    }
}
