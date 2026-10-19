import SwiftUI
import WebKit

// Read-only HTML viewer. Scripts are off and links leave the app, so untrusted repository pages stay inert.
struct HTMLPreview: NSViewRepresentable {
    let fileURL: URL
    let root: URL

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: URL?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else { decisionHandler(.allow); return }
            if url.scheme == "http" || url.scheme == "https" { NSWorkspace.shared.open(url) }
            decisionHandler(url.isFileURL ? .allow : .cancel)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != fileURL else { return }
        context.coordinator.loaded = fileURL
        view.loadFileURL(fileURL, allowingReadAccessTo: root)
    }
}

extension SourceLanguage {
    static func isPreviewable(path: String) -> Bool {
        ["html", "htm", "xhtml", "svg"].contains((path as NSString).pathExtension.lowercased())
    }
}
