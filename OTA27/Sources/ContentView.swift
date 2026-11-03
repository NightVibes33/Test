import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var diagnostics = AirliftDiagnostics()
    @StateObject private var pairing = PairingController.shared
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

                    GroupBox("3 · Pair this iPhone (no Mac)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Enable LocalDevVPN's local-tunnel mode, then pair this iPhone through iOS 27 Developer Mode. This happens entirely on the device.")
                                .font(.subheadline)
                            Button("Open LocalDevVPN") {
                                guard let url = URL(string: "localdevvpn://") else { return }
                                if UIApplication.shared.canOpenURL(url) {
                                    UIApplication.shared.open(url)
                                } else {
                                    diagnostics.status = "Unable to launch LocalDevVPN. Open the installed LocalDevVPN app manually and activate the local tunnel."
                                }
                            }
                            .buttonStyle(.bordered)
                            Button("Check local tunnel") { diagnostics.refreshTunnelStatus() }
                            Button("Discover NFCARD Remote Pairing port") { diagnostics.discoverPairingPort() }
                            Text(diagnostics.endpointStatus)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .buttonStyle(.bordered)
                            Text(diagnostics.tunnelStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(pairing.running ? "Pairing in progress…" : "Pair this iPhone") {
                                startOnDevicePairing()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(pairing.running || diagnostics.probing || diagnostics.monitoring)
                            if pairing.running {
                                Button("Cancel pairing") { pairing.softCancel() }
                                    .buttonStyle(.bordered)
                            }
                            Text(pairing.pairingStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let pin = pairing.pairingPIN {
                                Text("Pairing PIN: \(pin)")
                                    .font(.title2.monospacedDigit().bold())
                                    .textSelection(.enabled)
                            }
                            Text("While pairing: Settings → Privacy & Security → Developer Mode → Pair with OTA27 Blocker. Enter the PIN shown above. Return to OTA27 after approval.")
                                .font(.footnote)
                            Text(diagnostics.pairingPath == nil ? "Pairing record: not present" : "Pairing record saved; transport not verified")
                                .font(.caption.weight(.medium))
                            Button("Import an existing pairing file (optional)") { showPairingImporter = true }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("4 · AirLift diagnostics (experimental)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Powered by AirCard-iOS AirliftFFI. iOS 27.0.1 support is reported upstream; the exploit is reported patched in iOS 27.2 beta 3+. An on-device pairing record and working local tunnel are required.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(diagnostics.pairingPath == nil ? "Pairing: none" : "Pairing: ready")
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
                            Text(diagnostics.transportStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            diagnostics.refreshTunnelStatus()
            diagnostics.restoreStoredPairing()
        }
    }

    private func startOnDevicePairing() {
        guard !pairing.running else { return }
        diagnostics.status = "Starting on-device pairing. Approve the pairing PIN in Developer Mode."
        Task {
            do {
                let path = try await pairing.startAndWait()
                diagnostics.adoptPairing(at: path)
            } catch is CancellationError {
                diagnostics.status = "On-device pairing cancelled."
            } catch {
                diagnostics.status = "On-device pairing failed: \(error.localizedDescription)"
            }
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
