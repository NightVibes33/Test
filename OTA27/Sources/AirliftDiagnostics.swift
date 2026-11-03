import Foundation
import AirliftFFI

/// AirLift diagnostics are opt-in. No OTA settings or system plists are patched.
@MainActor
final class AirliftDiagnostics: ObservableObject {
    static let canaryTargets = [
        "/var/mobile/Library/Caches",
        "/var/mobile/Library/Preferences"
    ]
    private static weak var active: AirliftDiagnostics?

    @Published var pairingPath: String?
    @Published var targetHost = "10.7.0.1"
    @Published var tunnelStatus = "Tunnel status not checked"
    @Published var remotePairingPort: UInt16? = nil
    @Published var endpointStatus = "Remote Pairing port not discovered"
    @Published var transportStatus = "Device service connection not verified"
    @Published var selectedTarget = "/var/mobile/Library/Caches"
    @Published var monitoring = false
    @Published var probing = false
    @Published var status = "Pair this iPhone on-device or import a pairing file."
    @Published var canaryResult = "Not tested"
    @Published var logs: [String] = []

    init() {
        Self.active = self
        restoreStoredPairing()
        refreshTunnelStatus()
    }

    func restoreStoredPairing() {
        let path = PairingController.pairingFilePath()
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard bytes > 0 else { return }
        pairingPath = path
        if !monitoring && !probing {
            status = "A local pairing record is ready. Start LocalDevVPN before using AirLift."
        }
    }

    func adoptPairing(at path: String) {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard bytes > 0 else {
            status = "On-device pairing did not produce a usable record."
            return
        }
        pairingPath = PairingController.syncCanonicalPairingFile(from: path)
        transportStatus = "Pairing record saved, device connection unverified."
        status = "Pairing saved. Discover the live Remote Pairing port after starting LocalDevVPN."
        append("On-device RPPairing completed without a Mac (\(bytes) bytes).")
    }

    func refreshTunnelStatus() {
        let (vpn, _, detail) = NetworkStatus.summarize(deviceIP: targetHost)
        tunnelStatus = vpn
            ? "Tunnel interface detected — not proof LocalDevVPN is connected to device services."
            : "No tunnel interface detected. Activate LocalDevVPN in local-tunnel mode."
        append("Tunnel check: \(tunnelStatus) Interfaces: \(detail)")
    }

    /// NFCARD's Rust transport uses the advertised live Remote Pairing endpoint.
    nonisolated private static func configureTunnel(host: String, port: UInt16) -> Bool {
        host.withCString { al_connection_endpoint_set($0, port) } == 0
    }

    func discoverPairingPort() {
        endpointStatus = "Discovering _remotepairing._tcp…"
        RemotePairingPortDiscovery.shared.discover(timeout: 3.0) { [weak self] found in
            guard let self else { return }
            if let found {
                self.remotePairingPort = found
                self.endpointStatus = "Live Remote Pairing port: \(found)"
                self.append("Live Remote Pairing port discovered: \(found)")
            } else {
                self.endpointStatus = "No Bonjour port found, using NFCARD fallback 49152"
                self.append("No _remotepairing._tcp result; use NFCARD's fallback 49152.")
            }
        }
    }

    func importPairing(from url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty && data.count <= 2_000_000 else {
                status = "Invalid pairing file size."
                return
            }
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dest = folder.appendingPathComponent("ota27-pairing.plist")
            try data.write(to: dest, options: .atomic)
            pairingPath = dest.path
            status = "Pairing file imported. Enable the local VPN/tunnel before probing."
            append("Pairing credentials stored locally (not included in diagnostics export).")
        } catch {
            status = "Pairing import failed: \(error.localizedDescription)"
        }
    }

    func append(_ line: String) {
        logs.append("[\(Date().formatted(date: .omitted, time: .standard))] \(line)")
        if logs.count > 240 {
            logs.removeFirst(logs.count - 240)
        }
    }

    nonisolated private static func logFromBackground(_ line: String, onlyOTA: Bool) {
        if onlyOTA {
            let needle = line.lowercased()
            guard ["softwareupdate", "softwareupdated", "mobileasset", "gdmf.apple",
                   "mesu.apple", "ota update", "updatebrain"].contains(where: needle.contains)
            else { return }
        }
        Task { @MainActor in
            if onlyOTA { Self.active?.transportStatus = "Verified: receiving paired-device OTA syslog." }
            Self.active?.append(line)
        }
    }

    func startMonitoring() {
        guard !monitoring, !probing, let path = pairingPath else {
            status = "A pairing file is required, or another operation is running."
            return
        }
        monitoring = true
        status = "Connecting to the paired device's syslog stream…"
        let host = NetworkStatus.host(targetHost)
        RemotePairingPortDiscovery.shared.discover(timeout: 3.0) { [weak self] discoveredPort in
          guard let self else { return }
          let selectedPort = discoveredPort ?? self.remotePairingPort ?? 49152
          self.remotePairingPort = discoveredPort ?? self.remotePairingPort
          self.endpointStatus = "NFCARD Remote Pairing: \(host):\(selectedPort)"
          self.append("AirLift endpoint \(host):\(selectedPort) (\(discoveredPort == nil ? "fallback" : "live Bonjour")).")
          DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.configureTunnel(host: host, port: selectedPort)
            var error: UnsafeMutablePointer<CChar>? = nil
            let rc = path.withCString { pairingCString in
                al_syslog_stream_start(pairingCString, { _, line in
                    guard let line else { return }
                    AirliftDiagnostics.logFromBackground(String(cString: line), onlyOTA: true)
                }, nil, &error)
            }
            let description = error.map { String(cString: $0) }
            if let error { al_string_free(error) }
            Task { @MainActor in
                self.monitoring = false
                if rc != 0 { self.transportStatus = "Syslog connection failed: \(description ?? "code \(rc)")" }
                self.status = rc == 0 ? "Log stream stopped." :
                    "Log stream error: \(description ?? "code \(rc)")"
            }
          }
        }
    }

    func stopMonitoring() {
        guard monitoring else { return }
        al_syslog_stream_stop()
        status = "Stopping log stream…"
    }

    /// Uses upstream al_exploit_run: temporary canary write/read-back, not OTA modification.
    /// The upstream implementation stages Books sync state, tries to restore it, and reports
    /// cleanupComplete. This is NOT risk-free and MUST be initiated by the user.
    func runCanary() {
        guard !monitoring, !probing, let path = pairingPath,
              Self.canaryTargets.contains(selectedTarget) else {
            status = "Pair the device and select an allowed test target first."
            return
        }
        probing = true
        canaryResult = "Running AirTraffic canary (may temporarily touch Books sync metadata)…"
        let target = selectedTarget
        let host = NetworkStatus.host(targetHost)
        RemotePairingPortDiscovery.shared.discover(timeout: 3.0) { [weak self] discoveredPort in
          guard let self else { return }
          let selectedPort = discoveredPort ?? self.remotePairingPort ?? 49152
          self.remotePairingPort = discoveredPort ?? self.remotePairingPort
          self.endpointStatus = "NFCARD Remote Pairing: \(host):\(selectedPort)"
          self.append("AirLift endpoint \(host):\(selectedPort) (\(discoveredPort == nil ? "fallback" : "live Bonjour")).")
          DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.configureTunnel(host: host, port: selectedPort)
            var output: UnsafeMutablePointer<CChar>? = nil
            var error: UnsafeMutablePointer<CChar>? = nil
            let rc = path.withCString { pairingCString in
                target.withCString { targetCString in
                    al_exploit_run(pairingCString, targetCString, { _, msg in
                        guard let msg else { return }
                        AirliftDiagnostics.logFromBackground(String(cString: msg), onlyOTA: false)
                    }, nil, &output, &error)
                }
            }
            let json = output.map { String(cString: $0) } ?? ""
            let description = error.map { String(cString: $0) } ?? ""
            if let output { al_string_free(output) }
            if let error { al_string_free(error) }
            let dictionary = (json.data(using: .utf8)).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            let wrote = dictionary?["exactBytesRecovered"] as? Bool == true
            let cleaned = dictionary?["cleanupComplete"] as? Bool == true
            Task { @MainActor in
                self.probing = false
                if rc == 0 && wrote {
                    self.canaryResult = cleaned
                        ? "Confirmed temporary canary write/read-back; upstream reports cleanup complete. No OTA block proven."
                        : "Canary confirmed, but cleanup NOT confirmed. Inspect diagnostic logs before further testing."
                } else {
                    self.canaryResult = "Canary not confirmed: \(description.isEmpty ? "code \(rc)" : description)"
                }
                if rc != 0 && (description.contains("RemoteXPC") || description.contains("RSD") || description.contains("Device connection")) {
                    self.transportStatus = "Transport failure; pairing credentials are not necessarily invalid."
                }
                self.append("AirLift result: \(self.canaryResult)")
            }
          }
        }
    }

    func exportText() -> String {
        ("OTA27 Blocker — AirLift research diagnostics\n" +
         "Target: \(selectedTarget)\n" +
         "Canary: \(canaryResult)\n" +
         "NFCARD endpoint: \(endpointStatus)\n" +
         "Transport: \(transportStatus)\n" +
         "No pairing credentials exported.\n\n" +
         logs.joined(separator: "\n"))
    }
}
