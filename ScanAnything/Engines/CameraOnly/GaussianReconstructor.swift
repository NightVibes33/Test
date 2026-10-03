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
        iterations: Int32 = 8_000,
        progress: @escaping @MainActor @Sendable (_ fraction: Double, _ splats: Int) -> Void
    ) async throws -> Int {
        let datasetPath = datasetRoot.path(percentEncoded: false)
        let outputPath = outputURL.path(percentEncoded: false)

        return try await Task.detached(priority: .userInitiated) {
            // Preserve the full captured resolution. Training itself starts
            // progressively downscaled and reaches native resolution later.
            let dataset = GaussianDataset(path: datasetPath, downscaleFactor: 1.0)
            guard dataset.numTrain >= 48 else {
                throw GaussianReconstructionError.insufficientFrames(dataset.numTrain)
            }

            var configuration = TrainingConfig()
            configuration.iterations = iterations
            configuration.shDegree = 3
            configuration.shDegreeInterval = 1_000
            configuration.numDownscales = 2
            configuration.resolutionSchedule = 2_500
            configuration.warmupLength = 500
            configuration.refineEvery = 100
            configuration.stopScreenSizeAt = 6_000
            configuration.stopDensifyAt = min(5_500, max(3_000, iterations - 2_000))
            configuration.downscaleFactor = 1.0

            let trainer = GaussianTrainer(dataset: dataset, config: configuration)
            let total = max(1, Int(iterations))

            for index in 0..<total {
                if index % 25 == 0 {
                    try Task.checkCancellation()
                }
                let stats = trainer.step()
                if index % 25 == 0 || index == total - 1 {
                    let fraction = Double(index + 1) / Double(total)
                    let splats = stats.splatCount
                    await progress(fraction, splats)
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
