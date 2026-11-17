import SwiftUI
import WebKit

struct DeepAIWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        view.backgroundColor = UIColor.systemBackground
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url?.scheme != url.scheme || uiView.url?.host != url.host || uiView.url?.port != url.port {
            uiView.load(URLRequest(url: url))
        }
    }
}
