import Foundation
import SwiftUI

/// Launches the *actual* DeepAI 0.3.40 Node server in-process via NodeMobile.
/// Workspaces and settings remain in the iOS app sandbox. This is not a proxy
/// to an external Mac or PC.
@MainActor
final class EmbeddedDeepAIServer: ObservableObject {
    static let shared = EmbeddedDeepAIServer()

    enum Phase: Equatable {
        case preparing
        case booting
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var logTail = ""
    private var started = false
    private let endpoint = URL(string: "http://127.0.0.1:37730/")!
    var localURL: URL { endpoint }

    func launch() {
        guard !started else { return }
        started = true
        let manager = FileManager.default
        guard let serverRoot = Bundle.main.resourceURL?.appendingPathComponent("OriginalServer", isDirectory: true),
              manager.fileExists(atPath: serverRoot.appendingPathComponent("apps/server/dist/bin.mjs").path) else {
            phase = .failed("Original DeepAI Node server wasn't bundled. Check the DMG extraction step.")
            return
        }
        let appSupport = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let home = appSupport.appendingPathComponent("DeepAI", isDirectory: true)
        let workspace = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let log = home.appendingPathComponent("embedded-node.log")
        do {
            try manager.createDirectory(at: home, withIntermediateDirectories: true)
            try manager.createDirectory(at: workspace, withIntermediateDirectories: true)
        } catch {
            phase = .failed("Could not initialize iOS workspace: \(error.localizedDescription)")
            return
        }
        phase = .booting
        let entry = serverRoot.appendingPathComponent("apps/server/dist/bin.mjs").path
        let thread = Thread {
            let exitCode = EmbeddedNodeRunner.startScript(entry, workspace: workspace.path,
                                                          home: home.path, logFile: log.path)
            Task { @MainActor [weak self] in
                guard let self, self.phase != .ready else { return }
                self.phase = .failed("Original Node process exited (status \(exitCode)). Review the startup log.")
                self.readDiagnostics(path: log.path)
            }
        }
        thread.name = "DeepAI original Node.js backend"
        thread.stackSize = 4 * 1024 * 1024
        thread.qualityOfService = .userInitiated
        thread.start()
        Task { await awaitServer(log: log.path) }
    }

    private func awaitServer(log: String) async {
        for _ in 0..<80 {
            if case .failed = phase { return }
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 1
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if response is HTTPURLResponse {
                    phase = .ready
                    return
                }
            } catch {}
            try? await Task.sleep(for: .milliseconds(500))
        }
        readDiagnostics(path: log)
        phase = .failed("Original DeepAI server didn't start on the iPhone loopback address.")
    }

    func refreshDiagnostics() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let path = appSupport.appendingPathComponent("DeepAI/embedded-node.log").path
        readDiagnostics(path: path)
    }

    private func readDiagnostics(path: String) {
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            logTail = String(contents.suffix(12_000))
        } else {
            logTail = "No Node startup log was written."
        }
    }
}
