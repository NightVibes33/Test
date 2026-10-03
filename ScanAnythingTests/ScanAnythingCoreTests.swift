import Foundation
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

    @Test("Gaussian scan formats are identified as splats")
    func gaussianRecordDetection() {
        for fileName in ["model.ply", "model.spz", "model.splat"] {
            let record = ScanRecord(
                name: "Camera scan",
                engine: .cameraOnly,
                modelFileName: fileName,
                isMetricallyScaled: false
            )

            #expect(record.isGaussianSplat)
            #expect(record.isPreviewable == false)
        }
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
        #expect(quality.targetFrameCount <= 40)
        #expect(quality.minimumFrameCount <= 20)
        #expect(quality.maximumFrameCount >= quality.targetFrameCount)
        #expect(quality.minimumFeaturePoints >= 1_000)
        #expect(quality.maximumFeaturePoints >= 100_000)
        #expect(
            quality.maximumFeaturePoints + quality.depthPriorMaximumPoints <=
            250_000
        )

        #expect(quality.sharpnessWarmupFrames >= 6)
        #expect(quality.sharpnessFloorFraction >= 0.60)
        #expect(quality.minimumViewCoverage >= 0.25)
        #expect(quality.minimumViewCoverage <= 0.35)

        #expect(quality.trainingIterations == 30_000)
        #expect(quality.shDegree == 3)
        #expect(quality.ssimWeight == 0.20)
        #expect(quality.numDownscales == 3)
        #expect(quality.stopDensifyAt >= 10_000)
        #expect(quality.stopDensifyAt <= 12_000)
        #expect(
            quality.resolutionSchedule * quality.numDownscales <
            quality.stopDensifyAt
        )
        #expect(quality.stopDensifyAt < quality.trainingIterations)

        // Long native-resolution runs must bound transient iPhone pressure and
        // periodically wait for Metal so UI progress tracks completed GPU work.
        #expect(quality.imageCacheMB <= 256)
        #expect(quality.gpuSyncInterval <= 100)
        #expect(quality.memorySafetyHeadroomMB >= 256)
        #expect(
            quality.minimumEmergencyFinalizeIteration >
            quality.stopDensifyAt
        )
        #expect(
            quality.minimumEmergencyFinalizeIteration <
            quality.trainingIterations
        )
        #expect(quality.criticalThermalPauseMilliseconds >= 500)

        #expect(quality.learnedDepthPriorEnabled)
        #expect(quality.depthPriorKeyframeCount >= 16)
        #expect(quality.depthPriorMinimumAnchors >= 24)
        #expect(quality.depthPriorMaximumPoints >= 100_000)
        #expect(quality.depthPriorVoxelSize <= 0.004)
    }

    @Test("Universal capture keeps objects short while room scans collect broader coverage")
    func universalCapturePurposeThresholds() {
        #expect(CameraOnlyCapturePurpose.object.minimumFrameCount <= 20)
        #expect(CameraOnlyCapturePurpose.product.minimumFrameCount <= 24)
        #expect(
            CameraOnlyCapturePurpose.freeform.minimumFrameCount >
            CameraOnlyCapturePurpose.object.minimumFrameCount
        )
        #expect(CameraOnlyCapturePurpose.room.minimumFrameCount >= 60)
        #expect(CameraOnlyCapturePurpose.object.isolatesForeground)
        #expect(CameraOnlyCapturePurpose.product.isolatesForeground)
        #expect(CameraOnlyCapturePurpose.room.isolatesForeground == false)
    }

    @Test("Colored Gaussian seed PLY round-trips XYZ with RGB records")
    func coloredSeedPLYRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "scananything-colored-seed-\(UUID().uuidString).ply")
        defer { try? FileManager.default.removeItem(at: url) }

        let points = [
            SIMD3<Float>(0.1, 0.2, 0.3),
            SIMD3<Float>(-1.5, 2.25, 0.75)
        ]
        let colors = [
            SIMD3<UInt8>(255, 32, 16),
            SIMD3<UInt8>(1, 128, 240)
        ]

        try PointCloudFile.write(points: points, colors: colors, to: url)
        let roundTrip = try PointCloudFile.read(from: url)

        #expect(roundTrip == points)
    }

    @Test("Camera-only blur gate rejects a soft outlier after calibration")
    func cameraOnlyBlurGateRejectsSoftOutlier() {
        let quality = CameraOnlyQualityProfile.highDetail
        var gate = CameraOnlyFrameQualityGate(quality: quality)

        for _ in 0..<quality.sharpnessWarmupFrames {
            let accepted = gate.accepts(sharpness: 100)
            #expect(accepted)
        }

        let sharpAccepted = gate.accepts(sharpness: 80)
        #expect(sharpAccepted)

        let softAccepted = gate.accepts(sharpness: 30)
        #expect(softAccepted == false)
    }
}
