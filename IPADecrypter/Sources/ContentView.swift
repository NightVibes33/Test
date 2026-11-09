import SwiftUI
import UniformTypeIdentifiers

@main
struct IPADecrypterApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var importIPA = false
    @State private var inspected: IPAInspection?
    @State private var fileName: String?
    @State private var busy = false
    @State private var error: String?
    @State private var message = "Select an encrypted IPA to inspect it."
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("IPA Decrypter", systemImage: "lock.open.display")
                            .font(.largeTitle.bold())
                        Text("Native iOS FairPlay research + upstream ipadecrypt verification")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("No credential.bin import or Apple ID password needed for the device method.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }.padding(.top, 14)

                    DeviceFairPlayView()
                    
                    panel {
                        Label("Inspect another IPA", systemImage: "shippingbox")
                            .font(.headline)
                        Text("Importing an IPA can inspect its Mach-O encryption and license records. Apple's FairPlay service cannot decrypt a newly imported IPA from this app's data sandbox, so use a helper build with the licensed IPA embedded before installation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            importIPA = true
                        } label: {
                            Label(busy ? "Inspecting…" : "Import encrypted IPA", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                        if let name=fileName { Text(name).font(.caption.monospaced()).textSelection(.enabled) }
                        if let info=inspected {
                            LabeledContent("App", value: info.title)
                            LabeledContent("Bundle", value: info.identifier)
                            LabeledContent("Version", value: info.version)
                            LabeledContent("Encrypted 4 KB pages", value: "\(info.encryptedPages)")
                            LabeledContent("License records", value: info.hasLicenseRecords ? "Present" : "Not found")
                        }
                        Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.red)
                        }
                    }
                    DeviceAccessDiagnosticsView()
                    Text("Output IPAs are unsigned and must be re-signed for installation. Neither a successful build nor a sandbox extension proves FairPlay decryption until it runs on a licensed physical iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importIPA, allowedContentTypes: [.item], allowsMultipleSelection: false, onCompletion: handleImport)
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url=try result.get().first, url.pathExtension.lowercased()=="ipa" else {
                throw DecryptionFailure.invalid("Choose a valid .ipa file.")
            }
            let scope=url.startAccessingSecurityScopedResource()
            defer { if scope {url.stopAccessingSecurityScopedResource()} }
            let destination=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".ipa")
            try FileManager.default.copyItem(at:url,to:destination)
            fileName=url.lastPathComponent
            inspected=nil
            error=nil
            message="Inspecting Mach-O and FairPlay metadata…"
            busy=true
            Task {
                do {
                    let value=try await Task.detached(priority: .userInitiated) {
                        try IPAService.inspect(ipa: destination)
                    }.value
                    inspected=value
                    message = value.encryptedPages>0 ?
                        "FairPlay-encrypted. To use the credential-free backend, embed this licensed IPA in the helper build and install it on your device." :
                        "Main executable is not FairPlay-encrypted."
                } catch {
                    self.error=error.localizedDescription
                    message="Inspection failed."
                }
                busy=false
                try? FileManager.default.removeItem(at:destination)
            }
        } catch {
            self.error=error.localizedDescription
        }
    }
}
