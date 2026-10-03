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
        iterations: Int32 = 2_500,
        progress: @escaping @MainActor @Sendable (_ fraction: Double, _ splats: Int) -> Void
    ) async throws -> Int {
        let datasetPath = datasetRoot.path(percentEncoded: false)
        let outputPath = outputURL.path(percentEncoded: false)

        return try await Task.detached(priority: .userInitiated) {
            let dataset = GaussianDataset(path: datasetPath, downscaleFactor: 2.0)
            guard dataset.numTrain >= 10 else {
                throw GaussianReconstructionError.insufficientFrames(dataset.numTrain)
            }

            var configuration = TrainingConfig()
            configuration.iterations = iterations
            configuration.shDegree = 2
            configuration.shDegreeInterval = 500
            configuration.numDownscales = 1
            configuration.resolutionSchedule = 1_000
            configuration.warmupLength = 250
            configuration.refineEvery = 100
            configuration.stopDensifyAt = max(800, iterations / 2)

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

            let plyPath = outputURL
                .deletingPathExtension()
                .appendingPathExtension("ply")
                .path(percentEncoded: false)
            trainer.exportPly(to: plyPath)

            msplatSync()

            guard FileManager.default.fileExists(atPath: outputPath) else {
                throw GaussianReconstructionError.missingOutput
            }
            return trainer.splatCount
        }.value
    }
}
