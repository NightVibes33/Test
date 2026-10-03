import Foundation
import Msplat

enum GaussianReconstructionError: LocalizedError {
    case insufficientFrames(Int)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .insufficientFrames(let count):
            "Not enough usable camera views (\(count)). Scan more of the object and try again."
        case .missingOutput:
            "The 3D model finished processing but the output file was not created."
        }
    }
}

enum GaussianReconstructor {
    static func reconstruct(
        datasetRoot: URL,
        outputURL: URL,
        quality: CameraOnlyQualityProfile = .highDetail,
        progress: @escaping @MainActor @Sendable (_ fraction: Double, _ splats: Int) -> Void
    ) async throws -> Int {
        let datasetPath = datasetRoot.path(percentEncoded: false)
        let outputPath = outputURL.path(percentEncoded: false)

        return try await Task.detached(priority: .userInitiated) {
            // Keep the captured 4K source intact. msplat progressively trains
            // coarse-to-fine, then spends most of the 30K budget at native
            // resolution. The image cache remains bounded by msplat on iOS.
            let dataset = GaussianDataset(
                path: datasetPath,
                downscaleFactor: quality.datasetDownscaleFactor
            )
            guard dataset.numTrain >= quality.minimumFrameCount else {
                throw GaussianReconstructionError.insufficientFrames(dataset.numTrain)
            }

            var configuration = TrainingConfig()
            configuration.iterations = quality.trainingIterations
            configuration.shDegree = quality.shDegree
            configuration.shDegreeInterval = quality.shDegreeInterval
            configuration.ssimWeight = quality.ssimWeight
            configuration.numDownscales = quality.numDownscales
            configuration.resolutionSchedule = quality.resolutionSchedule
            configuration.warmupLength = quality.warmupLength
            configuration.refineEvery = quality.refineEvery
            configuration.resetAlphaEvery = quality.resetAlphaEvery
            configuration.densifyGradThresh = quality.densifyGradThresh
            configuration.densifySizeThresh = quality.densifySizeThresh
            configuration.stopScreenSizeAt = quality.stopScreenSizeAt
            configuration.stopDensifyAt = quality.stopDensifyAt
            configuration.splitScreenSize = quality.splitScreenSize
            configuration.downscaleFactor = quality.datasetDownscaleFactor

            let trainer = GaussianTrainer(dataset: dataset, config: configuration)
            let total = max(1, Int(quality.trainingIterations))

            for index in 0..<total {
                if index % 25 == 0 {
                    try Task.checkCancellation()
                }

                // Preserve the requested quality budget under sustained load.
                // Briefly yielding under thermal pressure is preferable to
                // reducing resolution, splat density, or iteration count.
                if index % 50 == 0 {
                    switch ProcessInfo.processInfo.thermalState {
                    case .serious:
                        try await Task.sleep(for: .milliseconds(35))
                    case .critical:
                        try await Task.sleep(for: .milliseconds(150))
                    case .nominal, .fair:
                        break
                    @unknown default:
                        break
                    }
                }

                let stats = trainer.step()
                if index % 25 == 0 || index == total - 1 {
                    await progress(
                        Double(index + 1) / Double(total),
                        stats.splatCount
                    )
                }
            }

            try Task.checkCancellation()
            msplatSync()

            // Keep the trained Gaussian parameters as float32. SPZ intentionally
            // quantizes position, scale, rotation, color, and SH coefficients;
            // PLY is the max-fidelity master and MetalSplatter/SplatIO can read it
            // directly for the in-app preview.
            trainer.exportPly(to: outputPath)
            msplatSync()

            guard FileManager.default.fileExists(atPath: outputPath) else {
                throw GaussianReconstructionError.missingOutput
            }
            return trainer.splatCount
        }.value
    }
}
