import ARKit
import RealityKit
import SwiftUI

struct CameraOnlyCaptureView: View {
    let purpose: CameraOnlyCapturePurpose

    @Environment(ScanStorage.self) private var storage
    @Environment(\.dismiss) private var dismiss

    @State private var engine: CameraOnlyCaptureEngine?
    @State private var startupError: String?

    init(purpose: CameraOnlyCapturePurpose = .object) {
        self.purpose = purpose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let engine {
                content(engine)
            } else if let startupError {
                failure(startupError)
            } else {
                ProgressView("Preparing camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task { startIfNeeded() }
        .onDisappear {
            guard let engine else { return }
            if case .done = engine.phase { return }
            engine.cancel()
        }
    }

    @ViewBuilder
    private func content(_ engine: CameraOnlyCaptureEngine) -> some View {
        switch engine.phase {
        case .idle:
            ProgressView("Preparing…").tint(.white)

        case .capturing:
            ZStack {
                ARCameraPreview(session: engine.session)
                    .ignoresSafeArea()
                captureOverlay(engine)
            }

        case .reconstructing:
            VStack(spacing: 20) {
                ProgressView(value: engine.processingProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .padding(.horizontal, 36)

                Text(engine.processingMessage)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("\(Int(engine.processingProgress * 100))% • \(engine.gaussianCount.formatted()) splats")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("Keep ScanAnything open while the iPhone finishes the model.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.white)

        case .done(let record):
            VStack(spacing: 18) {
                GaussianSplatView(url: storage.modelURL(for: record))
                    .frame(maxWidth: .infinity)
                    .frame(height: 430)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Label("Scan ready", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                if let count = record.imageCount {
                    Text("\(count) camera views • \((record.pointCount ?? 0).formatted()) splats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding()

        case .failed(let message):
            failure(message)

        case .cancelled:
            Color.clear.task { dismiss() }
        }
    }

    private func captureOverlay(_ engine: CameraOnlyCaptureEngine) -> some View {
        VStack {
            HStack {
                Button {
                    engine.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .tint(.white)
                .accessibilityLabel("Cancel scan")

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(engine.capturedCount) views")
                        .font(.caption.bold().monospacedDigit())
                    Text(engine.captureFormatDescription)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
            }

            Spacer()

            VStack(spacing: 12) {
                Text(engine.trackingMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.58), in: Capsule())

                VStack(spacing: 6) {
                    ProgressView(value: engine.coverage)
                        .tint(.white)
                    Text("Coverage \(Int(engine.coverage * 100))%")
                        .font(.caption.monospacedDigit())
                }
                .padding(12)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    engine.finish()
                } label: {
                    Text(engine.canFinish ? "Finish Scan" : "Keep Scanning")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(!engine.canFinish)
            }
        }
        .padding()
        .foregroundStyle(.white)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }

    private func startIfNeeded() {
        guard engine == nil else { return }
        let candidate = CameraOnlyCaptureEngine(storage: storage, purpose: purpose)
        do {
            try candidate.start()
            engine = candidate
        } catch {
            startupError = error.localizedDescription
        }
    }
}

private struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session = session
        view.environment.sceneUnderstanding.options = []
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        uiView.session.pause()
    }
}
