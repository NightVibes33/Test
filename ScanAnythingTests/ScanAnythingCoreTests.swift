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
    @Test("High-detail Camera 3D keeps native source resolution")
    func highDetailCameraQualityProfile() {
        let quality = CameraOnlyQualityProfile.highDetail

        #expect(quality.datasetDownscaleFactor == 1.0)
        #expect(quality.targetFrameCount >= 160)
        #expect(quality.minimumFrameCount >= 72)
        #expect(quality.maximumFrameCount >= quality.targetFrameCount)
        #expect(quality.minimumFeaturePoints >= 1_000)
        #expect(quality.trainingIterations >= 8_000)
        #expect(quality.shDegree == 3)
        #expect(quality.stopDensifyAt >= 5_500)
        #expect(quality.resolutionSchedule * quality.numDownscales < quality.trainingIterations)
    }

}
