import SwiftUI
import Foundation

struct WQResearchView: View {
    @State private var target = "/var/containers/Data/System"
    @State private var enableMarker = false
    @State private var running = false
    @State private var report: [String: Any] = [:]
    @State private var history: [[String: Any]] = []
    @State private var discoveredChildren: [String] = []
    @State private var reportFile: URL?
    @State private var errorMessage: String?

    private var outputRows: [(String, String)] {
        report.keys.filter { $0 != "childDirectories" }.sorted().map {
            ($0, String(describing: report[$0] ?? ""))
        }
    }

    var body: some View {
        Form {
            Section("Real container access research") {
                Text("Tests an actual worse_query sandbox extension. Not a root filesystem or kernel jailbreak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Existing target directory", text: $target)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))

                Toggle("Attempt a temporary write on tested children", isOn: $enableMarker)

                Text("Writes require your explicit toggle. The test uses a random exclusive-create file, exact read-back and cleanup. It never overwrites or deletes existing files. Root-level marker writes are refused by the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(running ? "Running test..." : "Run test on path above") {
                    runTest(path: target, tryMarker: enableMarker)
                }
                .disabled(running || target.isEmpty)
            }

            if !discoveredChildren.isEmpty {
                Section("Discovered children: tap to RUN a test") {
                    Text(enableMarker
                        ? "Temporary writes ENABLED: tapping a child immediately runs a read and exclusive temporary-marker test on that child."
                        : "Read-only: tapping a child immediately tests it and records the result. Enable the toggle above to attempt a temporary write too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(discoveredChildren, id: \.self) { child in
                        Button {
                            runTest(path: child, tryMarker: enableMarker)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URL(fileURLWithPath: child).lastPathComponent)
                                    .font(.footnote)
                                    .bold()
                                Text(child)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(enableMarker
                                    ? "RUN child read + temporary write"
                                    : "RUN child read")
                                    .font(.caption2)
                            }
                        }
                        .disabled(running)
                    }
                }
            }

            if !history.isEmpty {
                Section("Recorded test history (\(history.count))") {
                    ForEach(history.indices, id: \.self) { index in
                        let entry = history[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test \(index + 1): \(String(describing: entry["requestedPath"] ?? "UNKNOWN"))")
                                .font(.footnote)
                                .bold()
                            Text("Write requested: \((entry["markerRequested"] as? Bool) == true ? "YES" : "NO")")
                            Text("Extension: \(String(describing: entry["extension"] ?? "NOT_RECORDED"))")
                            Text("Read: \(String(describing: entry["extendedRead"] ?? "NOT_RECORDED"))")
                            Text("Marker: \(String(describing: entry["marker"] ?? "NOT_RECORDED"))")
                            Text("Cleanup: \(String(describing: entry["cleanup"] ?? "NOT_RECORDED"))")
                        }
                        .font(.caption)
                        .textSelection(.enabled)
                    }
                }

                Section("Most recent raw result") {
                    ForEach(outputRows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.0).font(.caption).bold()
                            Text(row.1)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Export all tests, not just the last one") {
                    Button("Prepare full JSON history (\(history.count) tests)") {
                        prepareExport()
                    }
                    .disabled(running)

                    if let reportFile {
                        ShareLink(item: reportFile) {
                            Label("Share all recorded results", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("WQ access research")
    }

    private func runTest(path: String, tryMarker: Bool) {
        guard !running, !path.isEmpty else { return }

        target = path
        running = true
        reportFile = nil
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = A18WQProbe(path, tryMarker) ?? [:]
            DispatchQueue.main.async {
                var recorded = result
                recorded["requestedPath"] = path
                recorded["markerRequested"] = tryMarker
                recorded["testIndex"] = history.count + 1
                history.append(recorded)
                report = recorded

                if let children = result["childDirectories"] as? [String] {
                    discoveredChildren = Array(Set(discoveredChildren).union(children)).sorted()
                }

                running = false
            }
        }
    }

    private func prepareExport() {
        do {
            let payload: [String: Any] = [
                "schemaVersion": 2,
                "runCount": history.count,
                "runs": history,
                "latest": report,
                "note": "Each run records its exact requested path and whether a marker write was requested. REFUSED is an app safeguard. DENIED is an OS error. No system-wide R/W is claimed."
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            let location = FileManager.default.temporaryDirectory
                .appendingPathComponent("A18Break-WQ-History-\(UUID().uuidString).json")
            try data.write(to: location, options: .atomic)
            reportFile = location
            errorMessage = nil
        } catch {
            reportFile = nil
            errorMessage = error.localizedDescription
        }
    }
}
