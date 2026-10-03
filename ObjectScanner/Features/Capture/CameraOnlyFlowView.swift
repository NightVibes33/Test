import ARKit
import SceneKit
import SwiftUI

struct CameraOnlyFlowView: View {
    @Environment(ScanStorage.self) private var storage
    @Environment(\.dismiss) private var dismiss

    @State private var engine: CameraOnlyCaptureEngine?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let engine {
                ARCameraPreview(session: engine.session)
                    .ignoresSafeArea()

                captureOverlay(engine)
            } else {
                Color.black.ignoresSafeArea()
                ProgressView("Starting camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .task {
            do {
                try await MainActor.run {
                    guard engine == nil else { return }
                    let newEngine = CameraOnlyCaptureEngine(storage: storage)
                    engine = newEngine
                    try newEngine.start()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onDisappear {
            if let engine, !isFinished(engine.phase) {
                engine.cancel()
            }
        }
        .alert(
            "Scan failed",
            isPresented: Binding(
                get: { errorMessage != nil || engine?.captureError != nil },
                set: { if !$0 { errorMessage = nil; engine?.clearCaptureError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
                engine?.clearCaptureError()
            }
        } message: {
            Text(errorMessage ?? engine?.captureError ?? "")
        }
    }

    @ViewBuilder
    private func captureOverlay(_ engine: CameraOnlyCaptureEngine) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    engine.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Cancel scan")

                Spacer()

                Text("\(engine.frameCount) views")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding()

            Spacer()

            if case .reconstructing(let progress) = engine.phase {
                reconstructionCard(progress)
            } else {
                captureCard(engine)
            }
        }
        .foregroundStyle(.white)
    }

    private func captureCard(_ engine: CameraOnlyCaptureEngine) -> some View {
        VStack(spacing: 14) {
            if let message = engine.trackingMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
            } else {
                Text(instruction(for: engine.frameCount))
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

            ProgressView(value: min(Double(engine.frameCount) / Double(engine.targetFrames), 1))
                .tint(.white)

            HStack {
                Label("\(engine.featurePointCount.formatted()) points", systemImage: "aqi.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        do {
                            _ = try await engine.finish()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Text(engine.canFinish ? "Create 3D" : "\(engine.minimumFrames - engine.frameCount) more")
                        .font(.headline)
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!engine.canFinish)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .padding()
    }

    private func reconstructionCard(_ progress: ReconstructionProgress) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: progress.fraction)
                .tint(.white)
            Text(progress.stage?.displayName ?? "Building your 3D scan…")
                .font(.headline)
            if let remaining = progress.remainingText {
                Text(remaining)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .padding()
    }

    private func instruction(for count: Int) -> String {
        switch count {
        case 0..<8: "Move slowly around the object"
        case 8..<24: "Keep the object centered and capture every side"
        case 24..<60: "Good — add higher and lower angles"
        default: "Great coverage. Create the 3D model when ready."
        }
    }

    private func isFinished(_ phase: ScanPhase) -> Bool {
        if case .done = phase { return true }
        return false
    }
}

private struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        if view.session !== session {
            view.session = session
        }
    }
}
