@preconcurrency import ARKit
import Foundation
import Observation

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
    private var workspace: ScanWorkspace?
    private var recorder: CameraOnlyFrameRecorder?
    private var reconstructionTask: Task<Void, Never>?

    private let targetFrameCount = 160
    private let minimumFrameCount = 72
    private(set) var phase: Phase = .idle
    private(set) var capturedCount = 0
    private(set) var featurePointCount = 0
    private(set) var trackingMessage = "Move slowly around the object"
    private(set) var processingProgress = 0.0
    private(set) var gaussianCount = 0
    private(set) var captureFormatDescription = "High quality"

    var coverage: Double {
        min(1, Double(capturedCount) / Double(targetFrameCount))
    }

    var canFinish: Bool {
        capturedCount >= minimumFrameCount && featurePointCount >= 1_000
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
        processingProgress = 0
        gaussianCount = 0
        trackingMessage = "Move slowly around the object"

        let recorder = CameraOnlyFrameRecorder(
            imagesURL: workspace.imagesURL
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

        // ARKit does not automatically guarantee a 4K camera feed. Explicitly
        // request its tracked 4K format when the device exposes one, then fall
        // back to ARKit's highest-quality supported format.
        if let format = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution
            ?? ARWorldTrackingConfiguration.supportedVideoFormats.first {
            configuration.videoFormat = format

            let width = Int(format.imageResolution.width)
            let height = Int(format.imageResolution.height)
            let longEdge = max(width, height)
            let prefix = longEdge >= 3_800 ? "4K" : "High quality"
            captureFormatDescription = "\(prefix) • \(width)×\(height) • \(format.framesPerSecond) fps"
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
            phase = .failed(
                "Keep scanning. Capture at least \(minimumFrameCount) well-tracked views around the object."
            )
            return
        }

        session.pause()
        session.delegate = nil
        phase = .reconstructing
        processingProgress = 0

        let snapshot = recorder.snapshot()
        let count = snapshot.frames.count
        let outputURL = workspace.root.appending(
            path: "model.spz",
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
                    outputURL: outputURL
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
                    modelFileName: "model.spz",
                    isMetricallyScaled: false,
                    imageCount: count,
                    pointCount: splats,
                    detail: nil,
                    summary: "Camera 3D"
                )
                storage.commit(record, workspace: workspace)
                self.workspace = nil
                self.recorder = nil
                phase = .done(record)
            } catch is CancellationError {
                storage.discard(workspace)
                self.workspace = nil
                self.recorder = nil
                phase = .cancelled
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
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
        case .progress(let count, let featurePointCount, let message):
            capturedCount = count
            self.featurePointCount = featurePointCount
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
