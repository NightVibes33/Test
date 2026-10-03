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
            // Keep the captured 4K source intact. msplat's progressive
            // resolution schedule controls training resolution without
            // destructively shrinking the dataset at load time.
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
            configuration.numDownscales = quality.numDownscales
            configuration.resolutionSchedule = quality.resolutionSchedule
            configuration.warmupLength = quality.warmupLength
            configuration.refineEvery = quality.refineEvery
            configuration.stopScreenSizeAt = quality.stopScreenSizeAt
            configuration.stopDensifyAt = quality.stopDensifyAt
            configuration.downscaleFactor = quality.datasetDownscaleFactor

            let trainer = GaussianTrainer(dataset: dataset, config: configuration)
            let total = max(1, Int(quality.trainingIterations))

            for index in 0..<total {
                if index % 25 == 0 {
                    try Task.checkCancellation()
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
            trainer.exportSpz(to: outputPath)
            msplatSync()

            guard FileManager.default.fileExists(atPath: outputPath) else {
                throw GaussianReconstructionError.missingOutput
            }
            return trainer.splatCount
        }.value
    }
}
