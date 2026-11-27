import SwiftUI
import UniformTypeIdentifiers

// Standalone equivalent of Filza's shared Device Pairing screen.
// No dependencies on Filza, 3105 or NFCARD's wallet UI.
struct StandalonePairingEntry: View {
    @ObservedObject var manager: DeviceManager
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label("Device Pairing", systemImage: "link.circle")
                .font(.subheadline.weight(.semibold))
        }
        .sheet(isPresented: $showing) {
            NavigationStack {
                StandaloneDevicePairingScreen(manager: manager)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = false }
                        }
                    }
            }
        }
    }
}

struct StandaloneDevicePairingScreen: View {
    @ObservedObject var manager: DeviceManager
    @ObservedObject private var pairing = ByeTunesOnDevicePairingController.shared
    @State private var showingImporter = false
    @State private var confirmForget = false
    @State private var message: String?
    private var supportsOnDevice: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    var body: some View {
        Form {
            Section("Device connection") {
                LabeledContent("Pairing record", value: manager.hasValidExpectedPairingFile ? "Validated" : "Not paired")
                LabeledContent("Required format", value: manager.expectedPairingFileTitle)
                LabeledContent("Device tunnel", value: manager.heartbeatReady ? "Connected" : manager.connectionStatus)
                Text("Enable LocalDevVPN before connecting. A saved pairing record does not guarantee an active tunnel.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(MP3SkullTheme.card)
            Section("Pair this iPhone") {
                Button {
                    pairing.start(manager: manager)
                } label: {
                    Label(pairing.isPairing ? "Pairing…" : "Start on-device pairing", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
                .disabled(pairing.isPairing || !supportsOnDevice)
                if pairing.isPairing { ProgressView() }
                Text(pairing.status).font(.footnote).foregroundStyle(.secondary)
                if let pin = pairing.pin {
                    LabeledContent("Pairing PIN", value: pin)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text(supportsOnDevice ? "Open Settings → Privacy & Security → Developer Mode → Pair with ByeTunes. Approve the request and enter the PIN." : "On-device pairing requires iOS 27. Import a pairing record instead.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(MP3SkullTheme.card)
            Section("Import an existing pairing record") {
                Button {
                    showingImporter = true
                } label: {
                    Label("Select pairing file", systemImage: "doc.badge.plus")
                }
                .disabled(pairing.isPairing)
                Text("Select a valid pairing record from Files. ByeTunes validates and stores it in its own private container.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .listRowBackground(MP3SkullTheme.card)
            Section("Connection tools") {
                Button {
                    manager.refreshExpectedPairingFileState()
                    manager.startHeartbeat(forceReconnect: true)
                } label: {
                    Label("Reconnect and refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!manager.hasValidExpectedPairingFile || pairing.isPairing)
                Button(role: .destructive) {
                    confirmForget = true
                } label: {
                    Label("Forget pairing", systemImage: "trash")
                }
                .disabled(!manager.hasValidExpectedPairingFile || pairing.isPairing)
            }
            .listRowBackground(MP3SkullTheme.card)
            if let message {
                Section("Status") { Text(message).font(.footnote) }
                    .listRowBackground(MP3SkullTheme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background { MP3SkullBackground() }
        .preferredColorScheme(.dark)
        .navigationTitle("Device Pairing")
        .task { manager.refreshExpectedPairingFileState() }
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
                message = "Pairing imported. Connecting through LocalDevVPN…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    manager.startHeartbeat(forceReconnect: true)
                }
            } catch {
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Forget local pairing records?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget pairing", role: .destructive) {
                manager.setAutoReconnectSuspended(true)
                defer { manager.setAutoReconnectSuspended(false) }
                do {
                    for file in [manager.rpPairingFile, manager.regularPairingFile] {
                        if FileManager.default.fileExists(atPath: file.path) {
                            try FileManager.default.removeItem(at: file)
                        }
                    }
                    manager.refreshExpectedPairingFileState()
                    message = "Local pairing records removed. No remote device settings changed."
                } catch {
                    manager.refreshExpectedPairingFileState()
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
