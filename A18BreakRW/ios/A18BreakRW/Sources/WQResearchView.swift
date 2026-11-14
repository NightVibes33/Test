import SwiftUI
import Foundation

struct WQResearchView: View {
    @State private var target = "/var/containers/Data/System"
    @State private var enableMarker = false
    @State private var running = false
    @State private var report: [String: Any] = [:]
    @State private var reportFile: URL?
    @State private var errorMessage: String?

    private var outputRows: [(String, String)] {
        report.keys.sorted().map { ($0, String(describing: report[$0] ?? "")) }
    }

    var body: some View {
        Form {
            Section("Measured access, not a jailbreak") {
                Text("worse_query requests a real sandbox extension using the app's signed App Group. This can reach selected containers on iOS 27, but not unrestricted root filesystem or kernel memory.")
                    .font(.footnote)
                TextField("Existing target directory", text: $target)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                Toggle("Try an exclusive temporary marker", isOn: $enableMarker)
                Text("A marker is only attempted in known data-container descendants. No existing file is modified or deleted. Some system-owned directories will still deny writes.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(running ? "Testing…" : "Attempt actual worse_query access") {
                    let requestedPath = target
                    let tryWrite = enableMarker
                    reportFile = nil
                    report = [:]
                    running = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = A18WQProbe(requestedPath, tryWrite) ?? [:]
                        DispatchQueue.main.async {
                            report = result
                            running = false
                            errorMessage = nil
                        }
                    }
                }.disabled(running || target.isEmpty)
            }
            if !report.isEmpty {
                Section("Actual results") {
                    ForEach(outputRows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.0).font(.caption).bold()
                            Text(row.1).font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                Section("Evidence export") {
                    Button("Prepare JSON report") { prepareExport() }
                    if let reportFile {
                        ShareLink(item: reportFile) { Label("Share report", systemImage: "square.and.arrow.up") }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
        }.navigationTitle("WQ access research")
    }

    private func prepareExport() {
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let location = FileManager.default.temporaryDirectory.appendingPathComponent("A18Break-WQ-\(UUID().uuidString).json")
            try data.write(to: location, options: .atomic)
            reportFile = location
        } catch { errorMessage = error.localizedDescription }
    }
}
