import Darwin
import Foundation
import Msplat
import os

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
    private static let logger = Logger(
        subsystem: "com.nightvibes33.scananything",
        category: "gaussian-reconstruction"
    )

    private static func availableMemoryMB() -> Int {
        let bytes = os_proc_available_memory()
        guard bytes > 0 else { return 0 }
        return Int(bytes) >> 20
    }

    static func reconstruct(
        datasetRoot: URL,
        outputURL: URL,
        quality: CameraOnlyQualityProfile = .highDetail,
        backgroundIsolated: Bool = false,
        progress: @escaping @MainActor @Sendable (_ fraction: Double, _ splats: Int) -> Void
    ) async throws -> Int {
        let datasetPath = datasetRoot.path(percentEncoded: false)
        let outputPath = outputURL.path(percentEncoded: false)

        return try await Task.detached(priority: .userInitiated) {
            // msplat's iOS default image cache is 512 MB. Native-resolution
            // training already carries large model + transient Metal buffers, so
            // use a tighter cache on 8 GB-class phones and reload frames as needed.
            setenv("MSPLAT_IMAGE_CACHE_MB", String(quality.imageCacheMB), 1)

            // Keep the captured 4K source intact. msplat progressively trains
            // coarse-to-fine, then spends most of the 30K budget at native
            // resolution.
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
            if backgroundIsolated {
                // Foreground-isolated training images are composited over black.
                // Matching the renderer background removes the incentive to grow
                // Gaussians just to explain the table or wall behind the object.
                configuration.bgColor = (0, 0, 0)
            }

            let trainer = GaussianTrainer(dataset: dataset, config: configuration)
            let total = max(1, Int(quality.trainingIterations))
            let syncEvery = max(1, quality.gpuSyncInterval)
            var splatCount = trainer.splatCount
            var emergencyFinalized = false

            await progress(0, splatCount)

            for index in 0..<total {
                if index % syncEvery == 0 {
                    try Task.checkCancellation()
                }

                // Drain Objective-C/Metal autoreleases every step instead of
                // letting a 30K-step detached task retain them until completion.
                let stats = autoreleasepool {
                    trainer.step()
                }
                splatCount = stats.splatCount

                let completed = index + 1
                let shouldSynchronize =
                    completed % syncEvery == 0 ||
                    completed == total

                guard shouldSynchronize else { continue }

                // trainer.step() submits Metal work asynchronously. Synchronizing
                // here keeps the command queue bounded and makes the displayed
                // percentage represent GPU-completed work instead of CPU-enqueued
                // work that can pile up and appear to freeze late in the run.
                msplatSync()
                try Task.checkCancellation()

                let trainingFraction = Double(completed) / Double(total)
                await progress(trainingFraction * 0.96, splatCount)

                let availableMB = Self.availableMemoryMB()
                if completed % 500 == 0 {
                    Self.logger.info(
                        "step=\(completed) splats=\(splatCount) availableMB=\(availableMB)"
                    )
                }

                // os_proc_available_memory is the remaining jetsam headroom on
                // iOS. If the phone is close to being killed after substantial
                // full-resolution training, preserve the current converged model
                // instead of risking a permanent late-stage stall/loss.
                if availableMB > 0,
                   availableMB <= quality.memorySafetyHeadroomMB,
                   completed >= quality.minimumEmergencyFinalizeIteration {
                    emergencyFinalized = true
                    Self.logger.warning(
                        "Finalizing early for memory safety at step=\(completed), availableMB=\(availableMB)"
                    )
                    break
                }

                // Real cooldown, not a token yield. Quality stays unchanged; only
                // wall time stretches when the A-series SoC reaches sustained
                // thermal pressure.
                switch ProcessInfo.processInfo.thermalState {
                case .serious:
                    try await Task.sleep(
                        for: .milliseconds(quality.seriousThermalPauseMilliseconds)
                    )
                case .critical:
                    try await Task.sleep(
                        for: .milliseconds(quality.criticalThermalPauseMilliseconds)
                    )
                case .nominal, .fair:
                    break
                @unknown default:
                    break
                }
            }

            try Task.checkCancellation()
            msplatSync()
            await progress(emergencyFinalized ? 0.97 : 0.975, splatCount)

            // Keep the trained Gaussian parameters as float32. SPZ intentionally
            // quantizes position, scale, rotation, color, and SH coefficients;
            // PLY is the max-fidelity master and MetalSplatter/SplatIO can read it
            // directly for the in-app preview.
            trainer.exportPly(to: outputPath)
            msplatSync()
            splatCount = trainer.splatCount
            await progress(1.0, splatCount)

            guard FileManager.default.fileExists(atPath: outputPath) else {
                throw GaussianReconstructionError.missingOutput
            }
            return splatCount
        }.value
    }
}
