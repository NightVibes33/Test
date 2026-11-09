import SwiftUI
import Network
import UIKit

struct DeviceAccessDiagnosticsView: View {
    @State private var importPairing = false
    @State private var pairingStatus = "No pairing record inspected"
    @State private var networkStatus = "Local RSD endpoint not tested"
    @State private var containerStatus = "Filesystem access not tested"
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("C · Pairing / LocalDevVPN diagnostics", systemImage: "network.badge.shield.half.filled")
                .font(.headline)
            Text("These checks are independent of FairPlay. A device pairing file, RSD tunnel and worse_query container access do NOT themselves reveal Apple account FairPlay credentials.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                importPairing = true
            } label: {
                Label("Inspect pairing plist locally", systemImage: "doc.badge.gearshape")
            }
            .buttonStyle(.bordered)
            Text(pairingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                probeRSD()
            } label: {
                if working { ProgressView() }
                Label("Probe LocalDevVPN / RSD on port 49152",systemImage:"cable.connector")
            }
            .buttonStyle(.bordered)
            .disabled(working)
            Text(networkStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                probeContainers()
            } label: {
                Label("Check baseline sandbox paths",systemImage:"folder")
            }
            .buttonStyle(.bordered)
            Text(containerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("worse_query is not silently embedded or activated by this diagnostic. Its published supported-version range does not establish compatibility with iOS 27.0.1. A sandbox listing is not evidence of Keychain or FairPlay credential access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Color(uiColor:.secondarySystemGroupedBackground), in:RoundedRectangle(cornerRadius:18))
        .fileImporter(isPresented:$importPairing,allowedContentTypes:[.item],allowsMultipleSelection:false) { result in
            do {
                guard let url=try result.get().first else {return}
                let scope=url.startAccessingSecurityScopedResource()
                defer {if scope {url.stopAccessingSecurityScopedResource()}}
                let bytes=try Data(contentsOf:url)
                try FairPlayCore.require(bytes.count > 64 && bytes.count < 2_000_000,"Unrecognized pairing record size")
                let plist=try PropertyListSerialization.propertyList(from:bytes,format:nil)
                try FairPlayCore.require(plist is [String:Any], "Pairing record must be a plist dictionary")
                // No pairing keys are retained, displayed, transmitted or used as Apple ID credentials.
                pairingStatus="Parsed plist locally (\(bytes.count) bytes); connectivity/authorization not established."
            } catch {
                pairingStatus="Cannot parse selected record: \(error.localizedDescription)"
            }
        }
    }

    private func probeRSD() {
        guard !working else {return}
        working=true
        networkStatus="Testing local TCP connection (127.0.0.1:49152)…"
        let endpoint=NWEndpoint.Host("127.0.0.1")
        let port=NWEndpoint.Port(rawValue:49152)!
        let connection=NWConnection(host:endpoint,port:port,using:.tcp)
        connection.stateUpdateHandler={state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    networkStatus="TCP endpoint responded. This does NOT establish pairing or account-key access."
                    working=false
                }
                connection.cancel()
            case .failed(let error):
                DispatchQueue.main.async {
                    networkStatus="No RSD connection at 127.0.0.1:49152: \(error.localizedDescription)"
                    working=false
                }
                connection.cancel()
            default:break
            }
        }
        connection.start(queue:DispatchQueue.global(qos:.utility))
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+5) {
            connection.cancel()
            DispatchQueue.main.async {
                if working {
                    working=false
                    networkStatus="Probe timed out; local RSD tunnel was not confirmed."
                }
            }
        }
    }

    private func probeContainers() {
        let paths=[
            "/var/mobile/Containers/Shared/AppGroup",
            "/var/containers/Data/System",
            "/var/containers/Shared/SystemGroup"
        ]
        let results=paths.map{ p -> String in
            do {
                let entries=try FileManager.default.contentsOfDirectory(atPath:p)
                return "\(p): readable (\(entries.count) entries)"
            } catch {
                return "\(p): inaccessible"
            }
        }
        containerStatus=results.joined(separator:"\n")
    }
}
