@preconcurrency import ARKit
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraOnlyCaptureEngine {
    enum Phase: Equatable {
        case idle
        case capturing
        case reconstructing
        case done(ScanRecord)
        case failed(String)
        case cancelled
    }

    let session = ARSession()

    private let storage: ScanStorage
    private let quality = CameraOnlyQualityProfile.highDetail
    private var workspace: ScanWorkspace?
    private var recorder: CameraOnlyFrameRecorder?
    private var reconstructionTask: Task<Void, Never>?

    private(set) var phase: Phase = .idle
    private(set) var capturedCount = 0
    private(set) var featurePointCount = 0
    private(set) var viewCoverage = 0.0
    private(set) var trackingMessage = "Orbit slowly around the object"
    private(set) var processingProgress = 0.0
    private(set) var gaussianCount = 0
    private(set) var captureFormatDescription = "High quality"

    var coverage: Double {
        guard quality.minimumViewCoverage > 0 else { return 0 }
        return min(1, viewCoverage / quality.minimumViewCoverage)
    }

    var canFinish: Bool {
        capturedCount >= quality.minimumFrameCount &&
        featurePointCount >= quality.minimumFeaturePoints &&
        viewCoverage >= quality.minimumViewCoverage
    }

    init(storage: ScanStorage) {
        self.storage = storage
    }

    func start() throws {
        guard DeviceCapabilities.supportsCameraOnly else {
            throw ScanEngineError.sessionUnavailable(
                "Camera-only AR scanning is not supported on this device."
            )
        }

        let workspace = try storage.makeWorkspace()
        self.workspace = workspace

        capturedCount = 0
        featurePointCount = 0
        viewCoverage = 0
        processingProgress = 0
        gaussianCount = 0
        trackingMessage = "Orbit slowly around the object"

        let recorder = CameraOnlyFrameRecorder(
            imagesURL: workspace.imagesURL,
            quality: quality
        ) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        self.recorder = recorder
        session.delegate = recorder
        session.delegateQueue = recorder.delegateQueue

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true
        configuration.environmentTexturing = .none
        configuration.videoHDRAllowed = false

        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution
            ?? ARWorldTrackingConfiguration.supportedVideoFormats.first {
            configuration.videoFormat = format

            let width = Int(format.imageResolution.width)
            let height = Int(format.imageResolution.height)
            let longEdge = max(width, height)
            let prefix = longEdge >= 3_800 ? "4K" : "High quality"
            captureFormatDescription =
                "\(prefix) • \(width)×\(height) • \(format.framesPerSecond) fps"
        }

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        phase = .capturing
    }

    func finish() {
        guard case .capturing = phase,
              let workspace,
              let recorder
        else { return }

        guard canFinish else {
            trackingMessage = "Keep scanning — fill missing angles and change height"
            return
        }

        session.pause()
        session.delegate = nil
        UIApplication.shared.isIdleTimerDisabled = true
        phase = .reconstructing
        processingProgress = 0

        let snapshot = recorder.snapshot()
        let count = snapshot.frames.count
        let outputURL = workspace.root.appending(
            path: "model.ply",
            directoryHint: .notDirectory
        )

        reconstructionTask?.cancel()
        reconstructionTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    try CameraOnlyDatasetWriter.write(
                        snapshot: snapshot,
                        to: workspace.root
                    )
                }.value

                try Task.checkCancellation()

                let splats = try await GaussianReconstructor.reconstruct(
                    datasetRoot: workspace.root,
                    outputURL: outputURL,
                    quality: quality
                ) { [weak self] progress, splatCount in
                    guard let self else { return }
                    self.processingProgress = progress
                    self.gaussianCount = splatCount
                }

                try Task.checkCancellation()

                if let heroFrame = snapshot.frames[safe: snapshot.frames.count / 2] {
                    let inputURL = workspace.root.appending(path: heroFrame.filePath)
                    let heroURL = workspace.root.appending(path: "hero.png")
                    _ = try? await Task.detached(priority: .utility) {
                        try await ObjectIsolationService.createTransparentPNG(
                            imageAt: inputURL,
                            outputURL: heroURL
                        )
                    }.value
                }

                try Task.checkCancellation()

                let record = ScanRecord(
                    id: workspace.id,
                    name: "3D Scan",
                    engine: .cameraOnly,
                    modelFileName: "model.ply",
                    isMetricallyScaled: false,
                    imageCount: count,
                    pointCount: splats,
                    detail: nil,
                    summary: "Camera 3D"
                )
                storage.commit(record, workspace: workspace)
                self.workspace = nil
                self.recorder = nil
                UIApplication.shared.isIdleTimerDisabled = false
                phase = .done(record)
            } catch is CancellationError {
                storage.discard(workspace)
                self.workspace = nil
                self.recorder = nil
                UIApplication.shared.isIdleTimerDisabled = false
                phase = .cancelled
            } catch {
                UIApplication.shared.isIdleTimerDisabled = false
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        UIApplication.shared.isIdleTimerDisabled = false
        reconstructionTask?.cancel()
        reconstructionTask = nil

        session.pause()
        session.delegate = nil
        recorder = nil

        if let workspace {
            storage.discard(workspace)
            self.workspace = nil
        }

        phase = .cancelled
    }

    private func handle(_ event: CameraOnlyCaptureEvent) {
        guard case .capturing = phase else { return }

        switch event {
        case .progress(
            let count,
            let featurePointCount,
            let viewCoverage,
            let message
        ):
            capturedCount = count
            self.featurePointCount = featurePointCount
            self.viewCoverage = viewCoverage
            trackingMessage = message
        case .failure(let message):
            trackingMessage = message
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
