import SwiftUI
import Network

struct DeviceAccessDiagnosticsView: View {
    private let groupID="group.com.nightvibes33.ipadecrypter"
    @State private var importPairing=false
    @State private var pairingStatus="No pairing record selected"
    @State private var rsdStatus="Local RSD connection not tested"
    @State private var worseStatus="No sandbox extension requested yet"
    @State private var running=false

    var body: some View {
        VStack(alignment:.leading,spacing:13) {
            Label("worse_query · Actual backend",systemImage:"folder.badge.gearshape")
                .font(.headline)
            Text("This build compiles forcequitOS's genuine worse_query.m engine and links its App Group sandbox-extension API. Test it only on directories listed in the published PoC; it does not retrieve Apple account keys.")
                .font(.footnote).foregroundStyle(.secondary)

            Button {
                probeWorseQuery()
            } label: {
                HStack {
                    if running {ProgressView()}
                    Label("Test worse_query sandbox extension",systemImage:"checkmark.shield")
                }
                .frame(maxWidth:.infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(running)
            Text(worseStatus)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Divider()

            Label("Optional device-service diagnostics",systemImage:"network")
                .font(.headline)
            Button {importPairing=true} label: {
                Label("Inspect pairing plist",systemImage:"doc")
            }
            .buttonStyle(.bordered)
            Text(pairingStatus).font(.caption).foregroundStyle(.secondary)

            Button {probeRSD()} label: {
                Label("Test LocalDevVPN loopback RSD",systemImage:"cable.connector")
            }
            .buttonStyle(.bordered)
            Text(rsdStatus).font(.caption).foregroundStyle(.secondary)
            Text("Neither an RSD TCP connection nor a pairing record proves FairPlay access. worse_query needs the signed App Group entitlement and a supported iOS build. It uses an App Group Library/Caches symlink temporarily; do not store user files in that directory.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))
        .fileImporter(isPresented:$importPairing,allowedContentTypes:[.item],allowsMultipleSelection:false) { result in
            do {
                guard let file=try result.get().first else {return}
                let scoped=file.startAccessingSecurityScopedResource()
                defer {if scoped{file.stopAccessingSecurityScopedResource()}}
                let d=try Data(contentsOf:file)
                try FairPlayCore.require(d.count>64 && d.count<2_000_000,"Pairing plist has unexpected length")
                let plist=try PropertyListSerialization.propertyList(from:d,format:nil)
                try FairPlayCore.require(plist is [String:Any],"Selected file is not a pairing plist dictionary")
                pairingStatus="Pairing plist parsed locally (\(d.count) bytes). No account credentials extracted or saved."
            } catch {
                pairingStatus="Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func probeWorseQuery() {
        guard !running else {return}
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:groupID) != nil else {
            worseStatus="The App Group is unavailable. Sign with a provisioning profile that authorizes \(groupID); ordinary ad-hoc signatures will not grant the group."
            return
        }
        running=true
        worseStatus="Attempting the real ContainerManager sandbox-extension flow…"
        let group=groupID
        Task {
            let output=await Task.detached(priority:.userInitiated) { () -> String in
                let paths=[
                    "/var/mobile/Containers/Shared/AppGroup",
                    "/var/containers/Data/System",
                    "/var/containers/Shared/SystemGroup"
                ]
                let fm=FileManager.default
                let os=ProcessInfo.processInfo.operatingSystemVersion
                return paths.map { path -> String in
                    let alternative=os.majorVersion == 26 && path.contains("/Containers/Shared/AppGroup")
                    let handle=worse_query(path,group,alternative,false)
                    guard handle >= 0 else {
                        let messages:[Int64:String]=[
                            -255:"path not found",
                            -1:"App Group unavailable",
                            -2:"unsupported ContainerManager symbols",
                            -3:"container query initialization failed",
                            -4:"group cache symlink could not be created",
                            -5:"ContainerManager query rejected",
                            -6:"kernel refused sandbox extension"
                        ]
                        return "\(path): \(messages[handle] ?? "error \(handle)")"
                    }
                    defer {worse_query_release(handle)}
                    do {
                        let entries=try fm.contentsOfDirectory(atPath:path)
                        return "\(path): extension granted; directory readable (\(entries.count) entries)"
                    } catch {
                        return "\(path): extension granted; listing denied (\(error.localizedDescription))"
                    }
                }.joined(separator:"\n")
            }.value
            worseStatus=output
            running=false
        }
    }

    private func probeRSD() {
        rsdStatus="Trying TCP 127.0.0.1:49152…"
        let conn=NWConnection(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:49152)!,using:.tcp)
        conn.stateUpdateHandler={ state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    rsdStatus="RSD TCP listener is reachable; device service authentication has not been verified."
                }
                conn.cancel()
            case .failed(let err):
                DispatchQueue.main.async {
                    rsdStatus="RSD loopback unavailable: \(err.localizedDescription)"
                }
                conn.cancel()
            default:break
            }
        }
        conn.start(queue:DispatchQueue.global(qos:.utility))
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+5) {
            conn.cancel()
        }
    }
}
