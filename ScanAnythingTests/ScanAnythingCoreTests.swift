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
}
