import SwiftUI

struct DeviceFairPlayView: View {
    @State private var selected:URL?
    @State private var result:DecryptionOutput?
    @State private var status="Checking for a FairPlay-licensed IPA embedded at build time."
    @State private var busy=false
    @State private var error:String?
    private var embedded:[URL] {DeviceFairPlayService.embeddedFolders()}

    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Label("B · Device-assisted FairPlay",systemImage:"iphone.gen3.radiowaves.left.and.right")
                .font(.headline)
            Text("Uses device FairPlay mapping instead of an exported Apple account credential. The encrypted app must already be embedded in this decryptor's installed bundle. Importing a new IPA after installation cannot use this mode.")
                .font(.footnote).foregroundStyle(.secondary)
            if embedded.isEmpty {
                Label("No embedded target app found",systemImage:"exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("To use this path, rebuild this helper with your licensed IPA included as an embedded payload. The build workflow accepts a private IPA URL as an Actions secret.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Embedded app",selection:$selected) {
                    Text("Choose target").tag(URL?.none)
                    ForEach(embedded,id:\.self) { url in
                        Text(url.lastPathComponent).tag(Optional(url))
                    }
                }
                .pickerStyle(.menu)
                .onAppear { if selected==nil {selected=embedded.first} }
                Button {
                    guard let selected, !busy else {return}
                    busy=true;error=nil;result=nil
                    status="Requesting licensed plaintext pages from iOS…"
                    Task {
                        do {
                            let value=try await Task.detached(priority:.userInitiated) {
                                try DeviceFairPlayService.decryptEmbedded(folder:selected)
                            }.value
                            result=value
                            status="Device-assisted decryption succeeded. The unsigned IPA is ready to share and re-sign."
                        } catch {
                            self.error=error.localizedDescription
                            status="Device decryption could not be verified."
                        }
                        busy=false
                    }
                } label: {
                    HStack {
                        if busy {ProgressView()}
                        Label("Decrypt embedded IPA on device",systemImage:"lock.open.iphone")
                    }
                    .frame(maxWidth:.infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected==nil || busy)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            if let error {
                Label(error,systemImage:"exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let result {
                Label("\(result.binaries) executable(s), \(result.pages) page(s) decrypted",
                      systemImage:"checkmark.shield.fill").foregroundStyle(.green)
                ShareLink(item:result.url) {
                    Label("Share device-decrypted IPA",systemImage:"square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))
    }
}
