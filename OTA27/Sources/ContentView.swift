import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var diagnostics = AirliftDiagnostics()
    @State private var showPairingImporter = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var connectivity = "Not checked"
    @State private var checking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("OTA27", systemImage: "iphone.gen3.radiowaves.left.and.right")
                            .font(.largeTitle.bold())
                        Text("Keep your current iOS version — profile installation and AirLift research")
                            .foregroundStyle(.secondary)
                        Text("A permanent system-level block has not been demonstrated.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    GroupBox("1 · Install the OTA DNS profile") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("This is the exact Mineek profile linked on kittymaxine.com. It routes DNS lookups for gdmf.apple.com through a third-party HTTPS resolver (https://hi.frcoal).")
                                .font(.subheadline)
                            Text("Installing the profile is a manual iOS Settings action. It may stop update discovery, but does not guarantee a permanent block.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Open original profile in Safari") {
                                UIApplication.shared.open(URL(string: "https://kittymaxine.com/blockota.mobileconfig")!)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Share bundled .mobileconfig") { shareProfile() }
                                .buttonStyle(.bordered)
                            Text("After downloading: Settings → Profile Downloaded (or General → VPN & Device Management) → Install. Confirm the DNS resolver before installing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("2 · Network diagnostic") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tests whether this app can reach gdmf.apple.com. A failed request does not prove iOS software updates are permanently disabled.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Result: \(connectivity)").font(.subheadline)
                            Button(checking ? "Checking…" : "Check update-catalog connectivity") {
                                checkCatalog()
                            }
                            .disabled(checking)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("3 · AirLift diagnostics (experimental)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Powered by AirCard-iOS AirliftFFI. iOS 27.0.1 support is reported upstream; the exploit is reported patched in iOS 27.2 beta 3+. A paired-device file and working local tunnel are required.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Import pairing file") { showPairingImporter = true }
                                .buttonStyle(.bordered)
                            Text(diagnostics.pairingPath == nil ? "Pairing: none" : "Pairing: imported")
                                .font(.caption)
                            TextField("Tunnel IP", text: $diagnostics.targetHost)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Button(diagnostics.monitoring ? "Stop OTA log scan" : "Start OTA log scan") {
                                    if diagnostics.monitoring {
                                        diagnostics.stopMonitoring()
                                    } else {
                                        diagnostics.startMonitoring()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(diagnostics.probing)
                            }
                            Picker("Canary target", selection: $diagnostics.selectedTarget) {
                                ForEach(AirliftDiagnostics.canaryTargets, id: \.self) { target in
                                    Text(target.replacingOccurrences(of: "/var/mobile/Library/", with: "Library/"))
                                        .tag(target)
                                }
                            }
                            .pickerStyle(.menu)
                            Text("Canary probe is NOT read-only: it temporarily stages sync data and a uniquely named test file. It never edits OTA configuration files. Failure/cleanup may leave temporary artifacts.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button(diagnostics.probing ? "Probing…" : "Run AirLift temporary canary") {
                                diagnostics.runCanary()
                            }
                            .disabled(diagnostics.probing || diagnostics.monitoring)
                            .buttonStyle(.bordered)
                            Text(diagnostics.canaryResult)
                                .font(.caption)
                            Text(diagnostics.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Export diagnostic text") { shareDiagnostics() }
                                .buttonStyle(.bordered)
                            ScrollView {
                                Text(diagnostics.logs.suffix(50).joined(separator: "\n"))
                                    .font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 180)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Manual fallback: Settings → General → Software Update → Automatic Updates → disable automatic downloads/installations where available. Deleting this app does not remove an installed profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("OTA27 Blocker")
        }
        .fileImporter(isPresented: $showPairingImporter, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                diagnostics.importPairing(from: url)
            case .failure(let error):
                diagnostics.status = "Import failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showShare) {
            ShareController(items: shareItems)
        }
    }

    private func shareProfile() {
        guard let url = Bundle.main.url(forResource: "blockota", withExtension: "mobileconfig") else {
            diagnostics.status = "Bundled profile missing; open the original URL instead."
            return
        }
        shareItems = [url]
        showShare = true
    }

    private func shareDiagnostics() {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("OTA27-diagnostics.txt")
        do {
            try diagnostics.exportText().write(to: destination, atomically: true, encoding: .utf8)
            shareItems = [destination]
            showShare = true
        } catch {
            diagnostics.status = "Cannot export diagnostics: \(error.localizedDescription)"
        }
    }

    private func checkCatalog() {
        guard let url = URL(string: "https://gdmf.apple.com/") else { return }
        checking = true
        connectivity = "Checking…"
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { _, response, error in
            let result: String
            if let response = response as? HTTPURLResponse {
                result = "Reachable (HTTP \(response.statusCode)); OTA blocking not established."
            } else if let error {
                result = "Connection failed (\(error.localizedDescription)); not proof of OTA blocking."
            } else {
                result = "No response; inconclusive."
            }
            DispatchQueue.main.async {
                checking = false
                connectivity = result
            }
        }.resume()
    }
}

private struct ShareController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
