import SwiftUI
import Foundation
import Darwin
import UIKit

struct ProbeEntry: Codable, Identifiable {
    let path: String
    let read: String
    let write: String
    let cleanup: String
    let entries: Int?
    var id: String { path }
}

struct ProbeEvidence: Codable {
    let generatedAt: Date
    let hardware: String
    let ios: String
    let build: String
    let effectiveUID: UInt32
    let effectiveGID: UInt32
    let results: [ProbeEntry]
    let note: String
}

enum RealAccessProbe {
    static let targets = [
        "/System/Library",
        "/usr/lib",
        "/private/var/mobile",
        "/private/var/mobile/Library",
        "/private/var/mobile/Media",
        "/private/var/mobile/Containers/Data/Application",
        "/private/var/containers",
        "/private/var/tmp"
    ]

    static func sysctlValue(_ key: String) -> String {
        var length: size_t = 0
        guard sysctlbyname(key, nil, &length, nil, 0) == 0, length > 0 else { return "UNAVAILABLE" }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname(key, &bytes, &length, nil, 0) == 0 else { return "UNAVAILABLE" }
        return String(cString: bytes)
    }

    private static func detail(_ operation: String, _ number: Int32) -> String {
        return "\(operation): errno=\(number) (\(String(cString: strerror(number))))"
    }

    static func run() -> ProbeEvidence {
        let folder = NSHomeDirectory() + "/Documents"
        let items = [folder] + targets
        let checked = items.map { directory in check(directory) }
        return ProbeEvidence(
            generatedAt: Date(),
            hardware: sysctlValue("hw.machine"),
            ios: UIDevice.current.systemVersion,
            build: sysctlValue("kern.osversion"),
            effectiveUID: geteuid(), effectiveGID: getegid(),
            results: checked,
            note: "Real POSIX access tests from the current signed app. A read PASS does not prove a sandbox escape. Write PASS is only the tested directory, not kernel R/W. Existing files are NEVER overwritten. No jailbreak or elevation included."
        )
    }

    private static func check(_ path: String) -> ProbeEntry {
        let fd = path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        var readStatus: String
        var count: Int?
        if fd >= 0 {
            close(fd)
            do {
                count = try FileManager.default.contentsOfDirectory(atPath: path).count
                readStatus = "PASS: directory opened and enumerated"
            } catch {
                readStatus = "PARTIAL: directory opened; enumeration failed (\((error as NSError).code))"
            }
        } else {
            let code = errno
            readStatus = detail("DENIED_OR_FAILED", code)
        }

        var st = stat()
        let code = path.withCString { lstat($0, &st) }
        guard code == 0 && (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            return ProbeEntry(path: path, read: readStatus, write: "NOT_TESTED: missing or not a direct directory", cleanup: "NOT_NEEDED", entries: count)
        }

        // An exclusive-create temporary marker is the ONLY modification attempted.
        // A file that already exists is never opened for writing.
        let marker = path + "/.a18break-" + UUID().uuidString + ".probe"
        let file = marker.withCString {
            open($0, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        }
        guard file >= 0 else {
            let failure = errno
            return ProbeEntry(path: path, read: readStatus,
                write: detail("DENIED_OR_FAILED", failure), cleanup: "NOT_NEEDED", entries: count)
        }

        let contents = Array("A18Break real R/W marker\n".utf8)
        var writeStatus = "FAILED: no confirmed read-back"
        contents.withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress else { return }
            let amount = Darwin.write(file, bytes, raw.count)
            if amount != raw.count {
                writeStatus = detail("FAILED write", amount < 0 ? errno : EIO)
                return
            }
            if fsync(file) != 0 {
                writeStatus = detail("FAILED fsync", errno)
                return
            }
            if lseek(file, 0, SEEK_SET) < 0 {
                writeStatus = detail("FAILED seek", errno)
                return
            }
            var received = [UInt8](repeating: 0, count: contents.count)
            let bytesRead = received.withUnsafeMutableBytes { dst in
                Darwin.read(file, dst.baseAddress!, dst.count)
            }
            writeStatus = bytesRead == contents.count && received == contents
                ? "PASS: created, wrote, fsynced and read back exact bytes"
                : "FAILED: read-back mismatch"
        }
        close(file)
        let removed = marker.withCString { unlink($0) }
        let cleanup = removed == 0 ? "PASS: marker removed" : detail("FAILED cleanup", errno)
        return ProbeEntry(path: path, read: readStatus,
                          write: writeStatus, cleanup: cleanup, entries: count)
    }
}

@main
struct A18BreakRWApp: App {
    var body: some Scene {
        WindowGroup { ProbeScreen() }
    }
}

struct ProbeScreen: View {
    @State private var evidence: ProbeEvidence?
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Target iPhone") {
                    LabeledContent("Model", value: RealAccessProbe.sysctlValue("hw.machine"))
                    LabeledContent("iOS", value: UIDevice.current.systemVersion)
                    LabeledContent("Build", value: RealAccessProbe.sysctlValue("kern.osversion"))
                    Text("Expected: iPhone17,3 / 24A446. Results are specific to this signed app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Actual read/write operations") {
                    Button("Run real R/W checks") {
                        evidence = RealAccessProbe.run()
                        exportURL = nil
                        exportError = nil
                    }
                    Text("The app tries real POSIX directory reads and exclusive temporary-file writes in its own Documents and selected protected directories. It never overwrites system files. Stock iOS should deny most protected writes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let results = evidence {
                    Section("Measured results") {
                        LabeledContent("Effective UID", value: String(results.effectiveUID))
                        LabeledContent("Effective GID", value: String(results.effectiveGID))
                        ForEach(results.results) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.path).font(.subheadline).bold()
                                Text("READ: \(entry.read)")
                                Text("WRITE: \(entry.write)")
                                Text("CLEANUP: \(entry.cleanup)")
                            }.font(.caption).textSelection(.enabled)
                        }
                    }
                    Section("Evidence export") {
                        Button("Prepare JSON for researcher") { export(results) }
                        if let url = exportURL {
                            ShareLink(item: url) { Label("Share JSON report", systemImage: "square.and.arrow.up") }
                        }
                        if let exportError { Text(exportError).foregroundStyle(.red).font(.caption) }
                    }
                }
                Section("Scope") {
                    Text("No exploit, privilege escalation, or kernel-memory access. A successful system directory read may be normal iOS behavior. A write PASS is only proof for that path under this app's permissions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("A18Break R/W Probe")
        }
    }

    private func export(_ report: ProbeEvidence) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("A18Break-RW-\(UUID().uuidString).json")
            try encoder.encode(report).write(to: url, options: [.atomic])
            exportURL = url
            exportError = nil
        } catch {
            exportURL = nil
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}
