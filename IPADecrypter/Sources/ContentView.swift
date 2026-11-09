import SwiftUI
import UniformTypeIdentifiers

@main
struct IPADecrypterApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var ipaURL: URL?
    @State private var inspection: IPAInspection?
    @State private var credential: Data?
    @State private var output: DecryptionOutput?
    @State private var importIPA = false
    @State private var importCredential = false
    @State private var busy = false
    @State private var status = "Choose an IPA to inspect its encryption."
    @State private var error: String?

    private var canDecrypt: Bool {
        ipaURL != nil && credential != nil && inspection?.encryptedPages ?? 0 > 0 && !busy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("IPA Decrypter",systemImage:"lock.open.display")
                            .font(.largeTitle.bold())
                        Text("Offline FairPlay decryption, on your iPhone")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("No Apple ID login, no cloud upload, no fake cryptid patch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    section("1 · Import IPA",systemImage:"shippingbox") {
                        Button {
                            importIPA = true
                        } label: {
                            Label(ipaURL == nil ? "Select encrypted IPA" : "Replace IPA",
                                  systemImage:"square.and.arrow.down")
                                .frame(maxWidth:.infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        if let ipaURL {
                            LabeledContent("File",value:ipaURL.lastPathComponent)
                        }
                        if let inspection {
                            Divider()
                            LabeledContent("App",value:inspection.title)
                            LabeledContent("Bundle",value:inspection.identifier)
                            LabeledContent("Version",value:inspection.version)
                            LabeledContent("Encrypted pages",value:"\(inspection.encryptedPages)")
                            LabeledContent("FairPlay license records",
                                           value:inspection.hasLicenseRecords ? "Found" : "Missing")
                            if inspection.encryptedPages==0 {
                                Label("Main executable already unencrypted",systemImage:"checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    section("2 · Authorized account credential",systemImage:"key.horizontal") {
                        Text("Import credential.bin (16 bytes) obtained from a supported device for the Apple account that owns this IPA. A pairing file, Apple ID password or certificate cannot replace it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                importCredential=true
                            } label: {
                                Label(credential == nil ? "Import credential.bin" : "Change credential",
                                      systemImage:"doc.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            if credential != nil {
                                Image(systemName:"checkmark.shield.fill").foregroundStyle(.green)
                                Button("Clear",role:.destructive) {
                                    credential=nil
                                    output=nil
                                    status="Credential cleared from app memory."
                                }
                            }
                        }
                        Text(credential == nil ? "Not loaded" : "16-byte credential loaded in memory only")
                            .font(.caption)
                            .foregroundStyle(credential == nil ? Color.secondary : Color.green)
                    }

                    section("A · Offline decrypt & rebuild IPA",systemImage:"arrow.triangle.2.circlepath") {
                        Button(action:beginDecryption) {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Label(busy ? "Working…" : "Decrypt & repackage",systemImage:"lock.open")
                            }
                            .frame(maxWidth:.infinity)
                            .padding(.vertical,4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canDecrypt)

                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let error {
                            Label(error,systemImage:"exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                        if let output {
                            Divider()
                            Label("\(output.binaries) binary(s), \(output.pages) encrypted page(s) decrypted",
                                  systemImage:"checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text(output.url.lastPathComponent)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            ShareLink(item:output.url) {
                                Label("Share decrypted IPA",systemImage:"square.and.arrow.up")
                                    .frame(maxWidth:.infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    DeviceFairPlayView()

                    DeviceAccessDiagnosticsView()

                    Label {
                        Text("Stock iOS does not grant access to other apps' decrypted runtime memory. This app performs real offline decryption only when the correct FairPlay credential is supplied. The resulting IPA needs a fresh signature before normal installation.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName:"info.circle")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.bottom,30)
                }
                .padding(.horizontal,20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor:.systemGroupedBackground))
            .fileImporter(isPresented:$importIPA,allowedContentTypes:[.item],allowsMultipleSelection:false) {
                handleIPA($0)
            }
            .fileImporter(isPresented:$importCredential,allowedContentTypes:[.item],allowsMultipleSelection:false) {
                handleCredential($0)
            }
        }
    }

    private func section<Content:View>(_ title:String,systemImage:String,
                                        @ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:13) {
            Label(title,systemImage:systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Color(uiColor:.secondarySystemGroupedBackground),
                    in:RoundedRectangle(cornerRadius:18))
    }

    private func selectedURL(_ result: Result<[URL],Error>) throws -> URL {
        guard let url=try result.get().first else {
            throw DecryptionFailure.invalid("No file selected")
        }
        return url
    }

    private func handleIPA(_ result:Result<[URL],Error>) {
        do {
            let url=try selectedURL(result)
            guard url.pathExtension.lowercased()=="ipa" else {
                throw DecryptionFailure.invalid("Select a .ipa file.")
            }
            let access=url.startAccessingSecurityScopedResource()
            defer { if access {url.stopAccessingSecurityScopedResource()} }
            let dest=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".ipa")
            try FileManager.default.copyItem(at:url,to:dest)
            ipaURL=dest
            inspection=nil
            output=nil
            error=nil
            busy=true
            status="Inspecting IPA archive and Mach-O encryption…"
            Task {
                do {
                    let info=try await Task.detached(priority:.userInitiated) {
                        try IPAService.inspect(ipa:dest)
                    }.value
                    inspection=info
                    status=info.encryptedPages==0
                        ? "This app's main executable is not FairPlay encrypted."
                        : "Found \(info.encryptedPages) encrypted 4 KB page(s). Supply the matching credential."
                } catch {
                    self.error=error.localizedDescription
                    status="Inspection failed."
                }
                busy=false
            }
        } catch {
            self.error=error.localizedDescription
        }
    }

    private func handleCredential(_ result:Result<[URL],Error>) {
        do {
            let url=try selectedURL(result)
            let access=url.startAccessingSecurityScopedResource()
            defer { if access {url.stopAccessingSecurityScopedResource()} }
            let bytes=try Data(contentsOf:url)
            try FairPlayCore.require(bytes.count==16,"Credential file must be exactly 16 bytes. Do not choose a pairing plist.")
            credential=bytes
            output=nil
            error=nil
            status="Credential imported. Ready for offline FairPlay processing."
        } catch {
            self.error=error.localizedDescription
        }
    }

    private func beginDecryption() {
        guard let ipa=ipaURL, let key=credential, !busy else {return}
        busy=true
        output=nil
        error=nil
        status="Decrypting FairPlay pages and rebuilding Payload…"
        Task {
            do {
                let result=try await Task.detached(priority:.userInitiated) {
                    try IPAService.decrypt(ipa:ipa,credential:key)
                }.value
                output=result
                status="Successful: generated a real decrypted IPA. Re-sign before installation."
            } catch {
                self.error=error.localizedDescription
                status="Decryption stopped; no fake IPA was produced."
            }
            busy=false
        }
    }
}
