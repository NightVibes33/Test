import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct OTAResearchApp: App {
    @StateObject private var model = OTAResearchModel()

    var body: some Scene {
        WindowGroup {
            OTAResearchView()
                .environmentObject(model)
        }
    }
}

struct OTAResearchView: View {
    @EnvironmentObject private var model: OTAResearchModel
    @State private var choosePairingFile = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("iOS", value: UIDevice.current.systemVersion)
                    LabeledContent("Pairing", value: model.hasPairing ? "Ready" : "Required")
                    LabeledContent("Tunnel", value: model.tunnelReady ? "Detected" : "Not detected")
                    HStack {
                        TextField("Device host", text: $model.deviceHost)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.numbersAndPunctuation)
                        Button("Refresh") { model.refreshStatus() }
                    }
                    Text("LocalDevVPN must be running, with a valid pairing file. AirLift is version-dependent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Connect") {
                    Button("Pair This Device") { model.startPairing() }
                        .disabled(model.isPairing)
                    Button("Import Pairing File") { choosePairingFile = true }
                    Text(model.pairingStatus)
                        .font(.footnote)
                        .textSelection(.enabled)
                }

                Section("OTA diagnostics") {
                    Button(model.isScanning ? "Stop OTA Log Scan" : "Start OTA Log Scan") {
                        if model.isScanning { model.stopScan() } else { model.startScan() }
                    }
                    .disabled(!model.hasPairing || model.isPairing)
                    Text("While scanning, open Settings → General → Software Update to trigger an update check. Only matching device syslog messages are collected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Run AirLift Canary Test (/var/tmp)") { model.runCanaryProbe() }
                        .disabled(!model.hasPairing || model.isProbing || model.isScanning)
                    Text("This optional test briefly writes a random canary file to /var/tmp, verifies it using AirLift, and requests cleanup. It never targets update settings or daemon files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Block OTA discovery") {
                    Button("Open OTA DNS Profile") {
                        UIApplication.shared.open(URL(string: "https://kittymaxine.com/blockota.mobileconfig")!)
                    }
                    Text("Installation requires approval in Settings. The linked profile routes lookups for gdmf.apple.com to third-party DNS-over-HTTPS. No profile installation or active-state verification is possible from this app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Disable automatic downloading and installation in Settings → General → Software Update → Automatic Updates.")
                        .font(.footnote)
                }

                Section("Observed results") {
                    LabeledContent("Matched lines", value: String(model.eventCount))
                    Text(model.status)
                        .font(.footnote)
                        .textSelection(.enabled)
                    Button("Export Research JSON") { exportURL = model.exportReport() }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Research JSON", systemImage: "square.and.arrow.up")
                        }
                    }
                    ForEach(Array(model.events.suffix(60).reversed()), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("Scope") {
                    Text("Observes logs mentioning softwareupdated, mobileassetd, MobileSoftwareUpdate, gdmf.apple.com, and update-related asset services. These are diagnostic hypotheses, not confirmed writable paths.")
                    Text("This build does not overwrite system plists, mutate OTA caches, disable daemons, or claim a permanent block.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("OTA Research")
        }
        .fileImporter(isPresented: $choosePairingFile, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): model.importPairing(from: url)
            case .failure(let error): model.status = "Import failed: \(error.localizedDescription)"
            }
        }
        .onAppear { model.refreshStatus() }
    }
}
