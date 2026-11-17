import Foundation
import SwiftUI

struct DeepAIHomeView: View {
    @AppStorage("deepai.serverURL") private var serverURL = ""
    @AppStorage("deepai.useBundledUI") private var useBundledUI = true
    @State private var showingSettings = false

    private var remote: URL? {
        ServerAddress.parse(serverURL)
    }

    var body: some View {
        Group {
            if let remote {
                Group {
                    if useBundledUI {
                        OriginalDeepAIClientView(remote: remote)
                    } else {
                        DeepAIWebView(url: remote)
                    }
                }
                .id("\(remote.absoluteString)-\(useBundledUI)")
                .overlay(alignment: .topTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(12)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Server settings")
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        ServerSettingsView(serverURL: $serverURL, useBundledUI: $useBundledUI)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingSettings = false }
                                }
                            }
                    }
                }
            } else {
                NavigationStack {
                    ServerSettingsView(serverURL: $serverURL, useBundledUI: $useBundledUI)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private enum ServerAddress {
    static func parse(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 2048,
              let url = URLComponents(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let hostname = url.host, !hostname.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            return nil
        }
        // Plain HTTP is only allowed for private-network hosts. Use HTTPS otherwise.
        if scheme == "http" && !isPrivateHost(hostname) { return nil }
        return url.url
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".local") { return true }
        let segments = h.split(separator: ".").compactMap { UInt8($0) }
        guard segments.count == 4 else { return false }
        if segments[0] == 10 || segments[0] == 127 { return true }
        if segments[0] == 192 && segments[1] == 168 { return true }
        if segments[0] == 172 && (16...31).contains(segments[1]) { return true }
        if segments[0] == 100 && (64...127).contains(segments[1]) { return true }
        return false
    }
}

struct ServerSettingsView: View {
    @Binding var serverURL: String
    @Binding var useBundledUI: Bool
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DeepAI Code")
                            .font(.title2.bold())
                        Text("Original 0.3.40 client on iOS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Coding-agent server") {
                TextField("https://your-computer.example", text: $draft)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($editing)
                    .onSubmit(save)
                Button("Connect") { save() }
                    .disabled(ServerAddress.parse(draft) == nil)
                if !draft.isEmpty && ServerAddress.parse(draft) == nil {
                    Text("Enter a server root URL. HTTPS is required outside your private network.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Interface") {
                Toggle("Use the original bundled DeepAI interface", isOn: $useBundledUI)
                Text("Bundled mode serves the React files extracted from your 0.3.40 DMG and proxies the original HTTP and WebSocket API to your computer. Direct mode loads the host's own frontend, which may be needed for sign-in flows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("The original Node.js coding agent, Git commands, shell, and workspace live on the host. iOS does not execute the macOS Electron binaries. This is an authentic iOS client port, not a fully standalone macOS-to-iOS binary conversion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = serverURL }
    }

    private func save() {
        guard let valid = ServerAddress.parse(draft) else { return }
        editing = false
        serverURL = valid.absoluteString
    }
}
