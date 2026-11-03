import Foundation
import SwiftUI
import UIKit
import AirliftFFI

@MainActor
final class OTAResearchModel: ObservableObject {
    // C callbacks run on Rust-owned threads and hop back to the main queue.
    static weak var active: OTAResearchModel?

    @Published var pairingStatus = "Import an existing pairing file or pair this device."
    @Published var status = "Ready for a read-only OTA syslog scan."
    @Published var events: [String] = []
    @Published var eventCount = 0
    @Published var isPairing = false
    @Published var isScanning = false
    @Published var isProbing = false
    @Published var hasPairing = false
    @Published var tunnelReady = false
    @Published var deviceHost = "10.7.0.1"

    private static let terms = [
        "softwareupdated", "softwareupdateservices", "mobilesoftwareupdate",
        "mobileassetd", "gdmf.apple.com", "softwareupdate", "assetbrain",
        "updatebrain", "sucontroller", "ota update"
    ]

    init() {
        Self.active = self
        refreshStatus()
    }

    func refreshStatus() {
        let path = PairingController.pairingFilePath()
        hasPairing = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0) ?? 0 > 0
        tunnelReady = NetworkStatus.loopbackTunnelUp(deviceIP: deviceHost)
    }

    private func configureTransport() {
        let host = deviceHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            _ = al_set_target_host(nil)
        } else {
            host.withCString { _ = al_set_target_host($0) }
        }
    }

    func importPairing(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                status = "Pairing file is empty."
                return
            }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dst = docs.appendingPathComponent("aircard_pairing.plist")
            try data.write(to: dst, options: .atomic)
            _ = PairingController.syncCanonicalPairingFile(from: dst.path)
            pairingStatus = "Imported: \(url.lastPathComponent)"
            refreshStatus()
        } catch {
            status = "Pairing import failed: \(error.localizedDescription)"
        }
    }

    func startPairing() {
        guard !isPairing else { return }
        isPairing = true
        pairingStatus = "Pair in iOS Settings when prompted."
        Task {
            do {
                _ = try await PairingController.shared.startAndWait()
                pairingStatus = "Pairing completed."
            } catch {
                pairingStatus = "Pairing failed: \(error.localizedDescription)"
            }
            isPairing = false
            refreshStatus()
        }
    }

    private func appendLine(_ line: String) {
        // Bound local memory; export includes only these matching log lines.
        eventCount += 1
        events.append(String(line.prefix(800)))
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    func startScan() {
        refreshStatus()
        guard hasPairing && !isScanning else {
            status = "A valid pairing file is required."
            return
        }
        configureTransport()
        isScanning = true
        status = "Listening for OTA syslog. Trigger an update check in Settings."
        let path = PairingController.pairingFilePath()

        let thread = Thread {
            var outError: UnsafeMutablePointer<CChar>? = nil
            let rc = path.withCString { pairPtr in
                al_syslog_stream_start(
                    pairPtr,
                    { _, raw in
                        guard let raw else { return }
                        let line = String(cString: raw)
                        let lower = line.lowercased()
                        guard OTAResearchModel.terms.contains(where: { lower.contains($0) }) else { return }
                        DispatchQueue.main.async {
                            OTAResearchModel.active?.appendLine(line)
                        }
                    },
                    nil,
                    &outError
                )
            }
            let message = outError.map { String(cString: $0) }
            if let outError { al_string_free(outError) }
            DispatchQueue.main.async {
                guard let model = OTAResearchModel.active else { return }
                model.isScanning = false
                model.status = rc == 0 ? "Scan finished." : "Scan ended: \(message ?? "rc=\(rc)")"
            }
        }
        thread.name = "OTAResearch.Syslog"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func stopScan() {
        al_syslog_stream_stop()
        status = "Stopping syslog stream…"
    }

    func runCanaryProbe() {
        refreshStatus()
        guard hasPairing && !isProbing && !isScanning else {
            status = "Pair first, then stop any active scan."
            return
        }
        configureTransport()
        isProbing = true
        status = "Testing temporary /var/tmp AirLift canary. No OTA files are touched."
        let path = PairingController.pairingFilePath()
        let thread = Thread {
            var resultJSON: UnsafeMutablePointer<CChar>? = nil
            var resultError: UnsafeMutablePointer<CChar>? = nil
            let rc = path.withCString { pairPtr in
                "/var/tmp".withCString { targetPtr in
                    al_exploit_run(
                        pairPtr, targetPtr,
                        { _, message in
                            guard let message else { return }
                            let line = String(cString: message)
                            DispatchQueue.main.async {
                                OTAResearchModel.active?.appendLine("AirLift: " + line)
                            }
                        },
                        nil,
                        &resultJSON,
                        &resultError
                    )
                }
            }
            let json = resultJSON.map { String(cString: $0) }
            let error = resultError.map { String(cString: $0) }
            if let resultJSON { al_string_free(resultJSON) }
            if let resultError { al_string_free(resultError) }
            DispatchQueue.main.async {
                guard let model = OTAResearchModel.active else { return }
                model.isProbing = false
                if let json { model.appendLine("Canary result: " + json) }
                model.status = rc == 0
                    ? "AirLift canary call succeeded. Review verification/cleanup fields in its result."
                    : "AirLift canary failed: \(error ?? "rc=\(rc)")"
            }
        }
        thread.name = "OTAResearch.Canary"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func exportReport() -> URL? {
        let payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "iOSVersion": UIDevice.current.systemVersion,
            "hardwareModel": UIDevice.current.model,
            "observedEventCount": eventCount,
            "eventsRetained": events,
            "currentStatus": status,
            "notes": [
                "Syslog visibility may be incomplete.",
                "Canary result is not evidence that OTA daemon configuration is writable.",
                "No update settings or daemons were modified."
            ]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("ota-research-\(UUID().uuidString).json")
            try data.write(to: path, options: .atomic)
            status = "Research JSON exported for sharing."
            return path
        } catch {
            status = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }
}
