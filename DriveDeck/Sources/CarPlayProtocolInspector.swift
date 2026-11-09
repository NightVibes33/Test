import Foundation
import Combine
import Network
import SwiftUI
import UIKit

/// Passive, consent-driven discovery of actual nearby CarPlay/AirPlay endpoints.
/// Deliberately does not impersonate an MFi accessory or claim pairing succeeded.
@MainActor
final class CarPlayProtocolInspector: ObservableObject {
    struct Service: Identifiable, Equatable {
        let id: String
        let type: String
        let name: String
        let endpointDescription: String
        let metadata: String
    }

    struct Event: Codable {
        let utc: String
        let category: String
        let message: String
    }

    @Published private(set) var services: [Service] = []
    @Published private(set) var events: [Event] = []
    @Published private(set) var state: String = "Not scanning"
    @Published private(set) var exportedFile: URL?
    private let queue = DispatchQueue(label: "com.nightvibes33.drivedeck.protocol-discovery")
    private let serviceTypes = [
        "_carplay-ctrl._tcp",
        "_airplay._tcp",
        "_raop._tcp",
        "_carcast-hu._tcp"
    ]
    private var browsers: [String: NWBrowser] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var activeProbes: [String: NWConnection] = [:]

    private func append(_ category: String, _ message: String) {
        events.append(Event(utc: ISO8601DateFormatter().string(from: Date()),
                            category: category,
                            message: message))
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    func start() {
        stop(silent: true)
        state = "Scanning for real CarPlay and AirPlay services"
        append("scan", "Started passive Bonjour scan on local network")
        for type in serviceTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browser.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch newState {
                    case .failed(let error):
                        self.append("error", "\(type): \(error.localizedDescription)")
                        self.state = "At least one Bonjour scan failed"
                    case .ready:
                        self.append("scan", "\(type): browser ready")
                    default: break
                    }
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let values: [(String, String, String, NWEndpoint)] = results.map { result in
                    let name: String
                    switch result.endpoint {
                    case let .service(serviceName, _, _, _): name = serviceName
                    default: name = result.endpoint.debugDescription
                    }
                    // Keep Bonjour TXT metadata printable for diagnostics, not authentication secrets.
                    return (name, result.endpoint.debugDescription,
                            String(describing: result.metadata), result.endpoint)
                }
                Task { @MainActor [weak self] in
                    self?.update(type: type, values: values)
                }
            }
            browsers[type] = browser
            browser.start(queue: queue)
        }
    }

    private func update(type: String, values: [(String, String, String, NWEndpoint)]) {
        let old = Set(services.filter { $0.type == type }.map(\.id))
        services.removeAll { $0.type == type }
        endpoints = endpoints.filter { !old.contains($0.key) }
        for (name, description, metadata, endpoint) in values {
            let id = type + "|" + description
            services.append(Service(id: id, type: type,
                                    name: name, endpointDescription: description,
                                    metadata: metadata))
            endpoints[id] = endpoint
            if !old.contains(id) {
                append("found", "\(type): \(name), endpoint \(description)")
            }
        }
        services.sort {
            $0.type == $1.type ? $0.name < $1.name : $0.type < $1.type
        }
        state = "Found \(services.count) service(s). This does not mean CarPlay paired."
    }

    func probe(_ service: Service) {
        guard let endpoint = endpoints[service.id] else {
            append("probe", "Endpoint disappeared: \(service.name)")
            return
        }
        if let previous = activeProbes[service.id] { previous.cancel() }
        append("probe", "Opening TCP transport to \(service.name) (\(service.type))")
        let connection = NWConnection(to: endpoint, using: .tcp)
        activeProbes[service.id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch newState {
                case .ready:
                    self.append("probe", "TCP reachable: \(service.name). CarPlay authentication NOT attempted.")
                    self.activeProbes.removeValue(forKey: service.id)
                    connection?.cancel()
                case .failed(let error):
                    self.append("error", "TCP failed \(service.name): \(error.localizedDescription)")
                    self.activeProbes.removeValue(forKey: service.id)
                    connection?.cancel()
                case .cancelled:
                    self.activeProbes.removeValue(forKey: service.id)
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }

    func stop(silent: Bool = false) {
        for browser in browsers.values { browser.cancel() }
        for connection in activeProbes.values { connection.cancel() }
        browsers.removeAll()
        endpoints.removeAll()
        activeProbes.removeAll()
        services.removeAll()
        state = "Stopped"
        if !silent { append("scan", "Stopped discovery and closed all probes") }
    }

    func clearEvents() {
        events.removeAll()
        exportedFile = nil
        append("log", "Log cleared")
    }

    func export() {
        struct Report: Encodable {
            let product: String
            let target: String
            let generatedUTC: String
            let explanation: String
            let os: String
            let services: [ServiceRecord]
            let events: [Event]
        }
        struct ServiceRecord: Encodable {
            let type: String
            let name: String
            let endpoint: String
            let metadata: String
        }
        let report = Report(
            product: "DriveDeck",
            target: "CarPlay and AirPlay passive protocol discovery",
            generatedUTC: ISO8601DateFormatter().string(from: Date()),
            explanation: "TCP reachability is not CarPlay, iAP2, MFi or AirPlay authentication. No private keys or pairing data are exported.",
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            services: services.map {
                ServiceRecord(type: $0.type, name: $0.name,
                              endpoint: $0.endpointDescription, metadata: $0.metadata)
            },
            events: events
        )
        do {
            let data = try JSONEncoder().encode(report)
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let file = folder.appendingPathComponent("DriveDeck-CarPlay-Protocol-Log.json")
            try data.write(to: file, options: .atomic)
            exportedFile = file
            append("export", "Saved protocol discovery diagnostics in Documents")
        } catch {
            append("error", "Cannot export diagnostics: \(error.localizedDescription)")
        }
    }

    deinit {
        for browser in browsers.values { browser.cancel() }
        for probe in activeProbes.values { probe.cancel() }
    }
}

struct ProtocolInspectorView: View {
    @StateObject private var inspector = CarPlayProtocolInspector()
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Read-only discovery of actual nearby CarPlay, AirPlay, and iCarCast Bonjour services. Probes test TCP reachability only; they cannot bypass MFi or establish a CarPlay session.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(inspector.state)
                        .font(.subheadline)
                    HStack {
                        Button("Scan") { inspector.start() }
                            .buttonStyle(.borderedProminent)
                        Button("Stop") { inspector.stop() }
                            .buttonStyle(.bordered)
                        Button("Export logs") {
                            inspector.export()
                            showShare = inspector.exportedFile != nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section("Discovered services (\(inspector.services.count))") {
                    if inspector.services.isEmpty {
                        Text("No endpoints discovered yet. Try the same Wi-Fi as an iCarCast or CarPlay receiver.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(inspector.services) { service in
                        Button {
                            inspector.probe(service)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(service.name).font(.headline)
                                Text(service.type).font(.caption).foregroundStyle(.blue)
                                Text(service.endpointDescription)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if service.metadata != "nil" {
                                    Text(service.metadata).font(.caption2)
                                        .foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                        }
                    }
                }
                Section("Protocol events (\(inspector.events.count))") {
                    ForEach(Array(inspector.events.indices.reversed()), id: \.self) { index in
                        let event = inspector.events[index]
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.category.uppercased())
                                .font(.caption2.bold()).foregroundStyle(.blue)
                            Text(event.message)
                                .font(.caption).textSelection(.enabled)
                            Text(event.utc).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Button("Clear logs", role: .destructive) { inspector.clearEvents() }
                }
            }
            .navigationTitle("CarPlay protocol inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { inspector.stop(); dismiss() }
                }
            }
            .onAppear { inspector.start() }
            .onDisappear { inspector.stop() }
            .sheet(isPresented: $showShare) {
                if let url = inspector.exportedFile {
                    DriveDiagnosticsShareSheet(url: url)
                }
            }
        }
    }
}

struct DriveDiagnosticsShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
