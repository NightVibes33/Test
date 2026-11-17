import SwiftUI

/// Standalone iOS engine. No remote computer address or server setup.
struct DeepAIHomeView: View {
    @StateObject private var backend = EmbeddedDeepAIServer.shared
    @State private var showDiagnostics = false

    var body: some View {
        Group {
            switch backend.phase {
            case .preparing, .booting:
                VStack(spacing: 18) {
                    ProgressView()
                    Text("Starting DeepAI Code")
                        .font(.headline)
                    Text("Loading the original 0.3.40 coding engine on this iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Startup diagnostics") {
                        backend.refreshDiagnostics()
                        showDiagnostics = true
                    }
                }.padding()
            case .ready:
                DeepAIWebView(url: backend.localURL)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            backend.refreshDiagnostics()
                            showDiagnostics = true
                        } label: {
                            Image(systemName: "waveform.path.ecg")
                                .padding(12)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Backend diagnostics")
                        .padding(10)
                    }
            case .failed(let message):
                ContentUnavailableView {
                    Label("DeepAI engine failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("View original Node logs") {
                        backend.refreshDiagnostics()
                        showDiagnostics = true
                    }
                }
            }
        }
        .task { backend.launch() }
        .sheet(isPresented: $showDiagnostics) {
            NavigationStack {
                ScrollView {
                    Text(backend.logTail)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Refresh") { backend.refreshDiagnostics() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDiagnostics = false }
                    }
                }
                .navigationTitle("Original Node backend")
            }
        }
        .preferredColorScheme(.dark)
    }
}
