import SwiftUI
import UIKit
import Darwin
import UniformTypeIdentifiers

struct AccessRecord: Codable, Identifiable {
    var id = UUID().uuidString
    let name: String
    let path: String
    let read: String
    let write: String
}

struct CrashRecord: Codable, Identifiable {
    var id = UUID().uuidString
    let process: String
    let fault: String
    let frame: String
    let offset: Int
    let matchesKnownCrash: Bool
}

@main
struct ResearchApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { AccessView() }
                    .tabItem { Label("Filesystem", systemImage: "folder") }
                NavigationStack { CrashesView() }
                    .tabItem { Label("Crash reports", systemImage: "waveform.path.ecg") }
            }
        }
    }
}

struct AccessView: View {
    @State private var results: [AccessRecord] = []
    @State private var showPicker = false
    @State private var status = "No probes run."
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("R/W capability evidence").font(.title2.bold())
                Text("Reports actual directory operations. Outside a granted folder, protected paths are READ-ONLY tests. This does not bypass iOS security or provide a jailbreak.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Run baseline") { runBaseline() }
                    .buttonStyle(.borderedProminent)
                Button("Select folder to test real read/write") { showPicker = true }
                    .buttonStyle(.bordered)
                ShareLink(item: JSONText.encode(results)) {
                    Label("Export JSON evidence", systemImage: "square.and.arrow.up")
                }.disabled(results.isEmpty)
                Text(status).font(.footnote)
                ForEach(results) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.headline)
                        Text(item.path)
                        Text("READ: " + item.read)
                        Text("WRITE: " + item.write)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding()
        }
        .navigationTitle("R/W Research")
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { choice in
            switch choice {
            case .failure(let error):
                status = error.localizedDescription
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                results.append(check("User-picked folder", url.path, writable: url))
                status = "Folder test done. Security scope granted: \(scoped)."
            }
        }
    }

    private func runBaseline() {
        let fm = FileManager.default
        let own: [(String, URL)] = [
            ("Documents", fm.urls(for: .documentDirectory, in: .userDomainMask)[0]),
            ("Caches", fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]),
            ("Temporary", fm.temporaryDirectory)
        ]
        var all = own.map { check($0.0, $0.1.path, writable: $0.1) }
        let outside: [(String, String)] = [
            ("Mobile home", "/private/var/mobile"),
            ("Mobile Library", "/private/var/mobile/Library"),
            ("App containers", "/private/var/mobile/Containers"),
            ("System Library", "/System/Library"),
            ("Rootless bootstrap", "/var/jb"),
            ("Root home", "/private/var/root")
        ]
        all += outside.map { check($0.0, $0.1, writable: nil) }
        results = all
        status = "Completed. No protected directory was modified."
    }

    private func check(_ name: String, _ path: String, writable: URL?) -> AccessRecord {
        let fd = path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        var read: String
        if fd < 0 {
            let e = errno
            read = "FAILED errno \(e): " + String(cString: strerror(e))
        } else {
            Darwin.close(fd)
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
                read = "PASS: enumerated \(files.count) entries (names withheld)"
            } else {
                read = "PARTIAL: opened, enumeration failed"
            }
        }
        return AccessRecord(name: name, path: path, read: read,
                            write: writable.map(writeMarker) ?? "NOT TESTED: no write authorization")
    }

    private func writeMarker(_ directory: URL) -> String {
        let id = UUID().uuidString
        let file = directory.appendingPathComponent(".rwresearch-\(id).txt")
        let data = Data(("test-" + id).utf8)
        do {
            try data.write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            guard try Data(contentsOf: file) == data else { return "FAIL: readback mismatch" }
            try FileManager.default.removeItem(at: file)
            return "PASS: created, verified, deleted"
        } catch { return "FAILED: " + error.localizedDescription }
    }
}

struct CrashesView: View {
    @State private var records: [CrashRecord] = []
    @State private var picking = false
    @State private var status = "Import original two-line JSON .ips reports."
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("PDF crash evidence").font(.title2.bold())
                Text("A matching fault only proves the rendering crash, not code execution or kernel access.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Import .ips files") { picking = true }
                    .buttonStyle(.borderedProminent)
                ShareLink(item: JSONText.encode(records)) {
                    Label("Export crash signatures", systemImage: "square.and.arrow.up")
                }.disabled(records.isEmpty)
                Text(status).font(.footnote)
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.matchesKnownCrash ? "MATCH: known Type-5 crash" : "Different crash")
                            .font(.headline)
                        Text(record.process)
                        Text(record.fault)
                        Text(record.frame + " offset \(record.offset)")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding()
        }
        .navigationTitle("Crash Evidence")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let error): status = error.localizedDescription
            case .success(let urls):
                var failed = 0
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        records.append(try parse(String(contentsOf: url, encoding: .utf8)))
                    } catch { failed += 1 }
                }
                status = "Parsed \(urls.count - failed); unreadable \(failed)."
            }
        }
    }
    private func parse(_ text: String) throws -> CrashRecord {
        let parts = text.split(separator: "\n", maxSplits: 1)
        guard parts.count == 2,
              let header = try JSONSerialization.jsonObject(with: Data(parts[0].utf8)) as? [String: Any],
              let body = try JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any]
        else { throw NSError(domain: "BadIPS", code: 1) }
        let process = body["procName"] as? String ?? header["app_name"] as? String ?? "unknown"
        let fault = (body["exception"] as? [String: Any])?["subtype"] as? String ?? "unknown"
        let threads = body["threads"] as? [[String: Any]] ?? []
        let thread = threads.first { $0["triggered"] as? Bool == true }
        let frame = (thread?["frames"] as? [[String: Any]])?.first ?? [:]
        let symbol = frame["symbol"] as? String ?? "unknown"
        let offset = frame["imageOffset"] as? Int ?? -1
        let matched = process == "CGPDFService" && symbol == "cg_shading_type5_draw"
            && offset == 1341668 && fault.contains("0x3ff000000000001c")
        return CrashRecord(process: process, fault: fault, frame: symbol,
                           offset: offset, matchesKnownCrash: matched)
    }
}

enum JSONText {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}