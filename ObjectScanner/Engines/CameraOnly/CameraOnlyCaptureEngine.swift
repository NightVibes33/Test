import ARKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CameraOnlyCaptureEngine: ScanEngine {
    static let kind: ScanEngineKind = .cameraOnly

    static var availability: EngineAvailability {
        guard ARWorldTrackingConfiguration.isSupported else {
            return .unsupportedDevice(reason: "World-tracking AR is not supported on this device.")
        }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            return .unsupportedDevice(reason: "A rear camera is required.")
        }
        return .available
    }

    private(set) var phase: ScanPhase = .idle
    private(set) var frameCount = 0
    private(set) var featurePointCount = 0
    private(set) var trackingMessage: String?
    private(set) var captureError: String?

    let session = ARSession()
    let targetFrames = 72
    let minimumFrames = 24
    var quality: CameraScanQuality

    var canFinish: Bool { frameCount >= minimumFrames }

    private let storage: ScanStorage
    private var workspace: ScanWorkspace?
    private var recorder: CameraOnlyFrameRecorder?

    init(storage: ScanStorage, quality: CameraScanQuality = .standard) {
        self.storage = storage
        self.quality = quality
    }

    func start() throws {
        guard Self.availability.isUsable else {
            throw ScanEngineError.sessionUnavailable(Self.availability.blockedReason ?? "Camera-only scanning is unavailable.")
        }

        phase = .preparing
        let workspace = try storage.makeWorkspace()
        self.workspace = workspace

        let recorder = CameraOnlyFrameRecorder(imagesURL: workspace.imagesURL) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        self.recorder = recorder
        session.delegate = recorder
        session.delegateQueue = recorder.delegateQueue

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none
        configuration.planeDetection = []

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        phase = .capturing(shots: 0, limit: targetFrames)
    }

    func finish() async throws -> ScanRecord {
        guard let workspace, let recorder else {
            throw ScanEngineError.sessionUnavailable("No camera-only scan is active.")
        }

        session.pause()
        session.delegate = nil

        let snapshot = recorder.snapshot()
        guard snapshot.frames.count >= minimumFrames else {
            let message = "Capture at least \(minimumFrames) views before finishing."
            phase = .failed(message: message)
            throw ScanEngineError.sessionUnavailable(message)
        }

        phase = .reconstructing(
            ReconstructionProgress(fraction: 0, stage: .preProcessing, estimatedRemaining: nil)
        )

        let output: CameraOnlyTrainingOutput
        do {
            output = try await CameraOnlyTrainer.reconstruct(
                snapshot: snapshot,
                workspaceRoot: workspace.root,
                quality: quality
            ) { [weak self] update in
                Task { @MainActor in
                    guard let self else { return }
                    let remainingSteps = Double(max(self.quality.iterations - update.iteration, 0))
                    let remaining = remainingSteps * Double(update.millisecondsPerStep) / 1_000
                    self.phase = .reconstructing(
                        ReconstructionProgress(
                            fraction: update.fraction,
                            stage: .optimization,
                            estimatedRemaining: remaining > 0 ? remaining : nil
                        )
                    )
                }
            }
        } catch {
            phase = .failed(message: error.localizedDescription)
            throw error
        }

        let record = ScanRecord(
            id: workspace.id,
            name: Self.defaultName(for: Date()),
            engine: Self.kind,
            modelFileName: output.spzURL.lastPathComponent,
            isMetricallyScaled: false,
            imageCount: snapshot.frames.count,
            pointCount: snapshot.featurePoints.count,
            detail: nil,
            summary: "Camera-only Gaussian Splat"
        )

        storage.commit(record, workspace: workspace)
        self.recorder = nil
        phase = .done(record)
        return record
    }

    func cancel() {
        session.pause()
        session.delegate = nil
        recorder = nil
        if let workspace {
            storage.discard(workspace)
            self.workspace = nil
        }
        phase = .cancelled
    }

    func clearCaptureError() {
        captureError = nil
    }

    private func handle(_ event: CameraOnlyCaptureEvent) {
        switch event {
        case .captured(let frameCount, let featurePointCount):
            self.frameCount = frameCount
            self.featurePointCount = featurePointCount
            phase = .capturing(shots: frameCount, limit: targetFrames)
        case .tracking(let message):
            trackingMessage = message
        case .failed(let message):
            captureError = message
        }
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Scan \(formatter.string(from: date))"
    }
}
