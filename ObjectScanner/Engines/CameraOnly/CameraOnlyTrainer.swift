import Foundation
import Msplat

enum CameraScanQuality: String, CaseIterable, Identifiable, Sendable {
    case quick
    case standard
    case maximum

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .maximum: "Maximum"
        }
    }

    var iterations: Int {
        switch self {
        case .quick: 800
        case .standard: 2_000
        case .maximum: 5_000
        }
    }

    var downscale: Float {
        switch self {
        case .quick: 4
        case .standard: 2
        case .maximum: 2
        }
    }
}

struct CameraOnlyTrainingProgress: Sendable {
    let fraction: Double
    let iteration: Int
    let splatCount: Int
    let millisecondsPerStep: Float
}

struct CameraOnlyTrainingOutput: Sendable {
    let spzURL: URL
    let plyURL: URL
}

enum CameraOnlyTrainer {
    enum TrainingError: LocalizedError {
        case noTrainingCameras
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .noTrainingCameras: "The captured dataset contains no usable training cameras."
            case .outputMissing: "3D reconstruction finished without producing a model."
            }
        }
    }

    static func reconstruct(
        snapshot: CameraOnlyRecorderSnapshot,
        workspaceRoot: URL,
        quality: CameraScanQuality,
        progress: @escaping @Sendable (CameraOnlyTrainingProgress) -> Void
    ) async throws -> CameraOnlyTrainingOutput {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try CameraOnlyDatasetWriter.write(snapshot, at: workspaceRoot)

            let dataset = GaussianDataset(path: workspaceRoot.path(percentEncoded: false), downscaleFactor: quality.downscale)
            guard dataset.numTrain > 0 else { throw TrainingError.noTrainingCameras }

            var configuration = TrainingConfig()
            configuration.iterations = Int32(quality.iterations)
            configuration.downscaleFactor = quality.downscale
            configuration.stopDensifyAt = Int32(max(quality.iterations / 2, 400))

            let trainer = GaussianTrainer(dataset: dataset, config: configuration)
            let updateEvery = max(quality.iterations / 80, 10)

            for index in 0..<quality.iterations {
                try Task.checkCancellation()
                let stats = trainer.step()
                if index % updateEvery == 0 || index == quality.iterations - 1 {
                    progress(
                        CameraOnlyTrainingProgress(
                            fraction: Double(index + 1) / Double(quality.iterations),
                            iteration: stats.iteration,
                            splatCount: stats.splatCount,
                            millisecondsPerStep: stats.msPerStep
                        )
                    )
                }
            }

            let spzURL = workspaceRoot.appending(path: "model.spz")
            let plyURL = workspaceRoot.appending(path: "model.ply")
            trainer.exportSpz(to: spzURL.path(percentEncoded: false))
            trainer.exportPly(to: plyURL.path(percentEncoded: false))

            guard FileManager.default.fileExists(atPath: spzURL.path(percentEncoded: false)) else {
                throw TrainingError.outputMissing
            }
            return CameraOnlyTrainingOutput(spzURL: spzURL, plyURL: plyURL)
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
