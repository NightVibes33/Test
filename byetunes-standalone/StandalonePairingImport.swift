import SwiftUI
import UniformTypeIdentifiers

struct StandalonePairingImport: View {
    @ObservedObject var manager: DeviceManager
    @State private var showingImporter = false
    @State private var message: String?
    @ObservedObject private var pairing = ByeTunesOnDevicePairingController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingImporter = true
            } label: {
                Label("Import Pairing File", systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(pairing.isPairing)
            if let message {
                Text(message).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                manager.setAutoReconnectSuspended(true)
                defer { manager.setAutoReconnectSuspended(false) }
                try manager.importPairingFile(from: url)
                manager.refreshExpectedPairingFileState()
                guard manager.hasValidExpectedPairingFile else {
                    message = "The imported pairing record did not validate."
                    return
                }
                message = "Pairing record imported. Connecting through LocalDevVPN…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    manager.startHeartbeat(forceReconnect: true)
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
