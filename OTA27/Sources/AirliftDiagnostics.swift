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
    @Published var selectedTarget = "/var/mobile/Library/Caches"
    @Published var monitoring = false
    @Published var probing = false
    @Published var status = "Import a local pairing file to enable AirLift diagnostics."
    @Published var canaryResult = "Not tested"
    @Published var logs: [String] = []

    init() {
        Self.active = self
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
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInitiated).async {
            host.withCString { _ = al_set_target_host($0) }
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
                self.status = rc == 0 ? "Log stream stopped." :
                    "Log stream error: \(description ?? "code \(rc)")"
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
            status = "Import pairing and select an allowed test target first."
            return
        }
        probing = true
        canaryResult = "Running AirTraffic canary (may temporarily touch Books sync metadata)…"
        let target = selectedTarget
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.global(qos: .userInitiated).async {
            host.withCString { _ = al_set_target_host($0) }
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
                self.append("AirLift result: \(self.canaryResult)")
            }
        }
    }

    func exportText() -> String {
        ("OTA27 Blocker — AirLift research diagnostics\n" +
         "Target: \(selectedTarget)\n" +
         "Canary: \(canaryResult)\n" +
         "No pairing credentials exported.\n\n" +
         logs.joined(separator: "\n"))
    }
}
