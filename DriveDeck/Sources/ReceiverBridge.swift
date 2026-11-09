import Foundation
import SwiftUI
import WebKit
import Security
import Combine

/// Stores a receiver-viewer URL (possibly containing a short-lived bearer token)
/// in the iOS Keychain. It never enters analytics, logs, UserDefaults, or the repo.
@MainActor
final class ReceiverConnectionStore: ObservableObject {
    @Published var hasSavedReceiver = false
    @Published var diagnostic = "Not connected"
    @Published var lastPageTitle = ""

    private let service = "com.nightvibes33.drivedeck.receiver"
    private let account = "trusted-viewer-url"

    init() {
        hasSavedReceiver = (readURL() != nil)
    }

    func readURL() -> URL? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return Self.validURL(value)
    }

    static func validURL(_ raw: String) -> URL? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count < 2048, !cleaned.contains(where: { $0.isNewline }),
              let components = URLComponents(string: cleaned),
              components.scheme?.lowercased() == "https",
              let hostname = components.host, !hostname.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    func save(rawURL: String) -> Bool {
        guard let url = Self.validURL(rawURL) else {
            diagnostic = "A full HTTPS receiver URL is required."
            return false
        }
        let data = Data(url.absoluteString.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var updated = base
        updated[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        updated[kSecValueData as String] = data
        let code = SecItemAdd(updated as CFDictionary, nil)
        hasSavedReceiver = code == errSecSuccess
        diagnostic = hasSavedReceiver
            ? "Receiver address saved securely on this device."
            : "Could not save receiver address in Keychain (OSStatus: \(code))."
        return hasSavedReceiver
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        hasSavedReceiver = false
        diagnostic = "Saved receiver removed."
        lastPageTitle = ""
    }
}

/// Hosts an actual remote CarPlay media viewer provided by an authenticated receiver.
/// No receiver handshake occurs in this app; remote service performs iAP2/MFi/transport.
struct CarPlayViewerBrowser: UIViewRepresentable {
    let url: URL
    @Binding var state: String
    @Binding var pageTitle: String

    func makeCoordinator() -> Delegate {
        Delegate(state: $state, pageTitle: $pageTitle, initialOrigin: Self.origin(url))
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor.black
        web.scrollView.backgroundColor = UIColor.black
        web.scrollView.bounces = false
        web.allowsBackForwardNavigationGestures = false
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func origin(_ url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return "" }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    final class Delegate: NSObject, WKNavigationDelegate {
        @Binding var state: String
        @Binding var pageTitle: String
        private let initialOrigin: String
        init(state: Binding<String>, pageTitle: Binding<String>, initialOrigin: String) {
            _state = state
            _pageTitle = pageTitle
            self.initialOrigin = initialOrigin
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let dest = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame != false,
               dest.scheme != "about", CarPlayViewerBrowser.origin(dest) != initialOrigin {
                // Never leak the bearer-token URL to a different origin through redirects.
                state = "Cross-origin navigation blocked. Check the receiver URL."
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state = "Opening authenticated receiver viewer..."
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageTitle = webView.title ?? ""
            state = "Viewer webpage loaded. The receiver must pair with an iPhone for live CarPlay video."
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state = "Receiver page unavailable: " + error.localizedDescription
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state = "Receiver view error: " + error.localizedDescription
        }
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Do not skip TLS verification even if a receiver offers a self-signed cert.
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

struct AuthenticatedCarPlayViewer: View {
    let address: URL
    @State private var status = "Loading..."
    @State private var pageTitle = ""
    @State private var reloadID = UUID()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CarPlayViewerBrowser(url: address, state: $status, pageTitle: $pageTitle)
                    .id(reloadID)
                    .background(Color.black)
                HStack(spacing: 7) {
                    Circle().fill(.orange).frame(width: 7, height: 7)
                    Text(status)
                        .font(.caption)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
            }
            .navigationTitle(pageTitle.isEmpty ? "CarPlay receiver" : pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reloadID = UUID()
                        status = "Reconnecting..."
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct ReceiverBridgeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var connection = ReceiverConnectionStore()
    @State private var enteredURL = ""
    @State private var showViewer = false
    @State private var showRemoveConfirmation = false
    @State private var currentURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Authenticated CarPlay stream") {
                    Text("Display and control CarPlay generated by a real, separately running receiver such as PlayPort. This connection is a viewer, not a standalone iPhone head unit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    SecureField("https://receiver:port/?token=...", text: $enteredURL)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .privacySensitive()

                    HStack(spacing: 12) {
                        Button {
                            if connection.save(rawURL: enteredURL) {
                                currentURL = connection.readURL()
                                showViewer = currentURL != nil
                                enteredURL = ""
                            }
                        } label: {
                            Label("Save & Open", systemImage: "display")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ReceiverConnectionStore.validURL(enteredURL) == nil)

                        if connection.hasSavedReceiver {
                            Button("Open saved") {
                                currentURL = connection.readURL()
                                showViewer = currentURL != nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if connection.hasSavedReceiver {
                        Button(role: .destructive) { showRemoveConfirmation = true } label: {
                            Label("Forget receiver URL", systemImage: "trash")
                        }
                    }
                    Text(connection.diagnostic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("What's real") {
                    Label("Live media is decoded by the receiver's web client when available", systemImage: "video.fill")
                    Label("Touch goes through the receiver's authenticated HID path", systemImage: "hand.tap.fill")
                    Label("Receiver requires separately running server and accessory identity", systemImage: "server.rack")
                }
                Section("Security & setup") {
                    Text("1. Start a compatible CarPlay receiver on your own Mac or server with its authorized accessory identity.")
                    Text("2. Pair the transmitting iPhone to that receiver.")
                    Text("3. Open the receiver's HTTPS viewer URL here. Do not share its token.")
                    Text("4. If the receiver uses a self-signed certificate, first establish trust in iOS. DriveDeck never disables TLS verification.")
                    Text("The receiver may require WebCodecs support in WebKit. Some servers support desktop browsers only. A page loading does not prove a CarPlay session.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            .navigationTitle("Real CarPlay viewer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showViewer) {
                if let currentURL {
                    AuthenticatedCarPlayViewer(address: currentURL)
                }
            }
            .confirmationDialog("Forget this receiver?", isPresented: $showRemoveConfirmation) {
                Button("Delete saved address", role: .destructive) {
                    connection.clear()
                    currentURL = nil
                }
            }
        }
    }
}
