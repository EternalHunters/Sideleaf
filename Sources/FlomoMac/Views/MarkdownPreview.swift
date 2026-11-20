import SwiftUI
import SwiftData
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let settings = WKWebViewConfiguration()
        settings.defaultWebpagePreferences.allowsContentJavaScript = false
        settings.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: settings)
        webView.navigationDelegate = context.coordinator
        webView.setAccessibilityLabel("Markdown 预览")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.markdown != markdown else { return }
        context.coordinator.markdown = markdown
        webView.loadHTMLString(Self.page(containing: MarkdownHTML.render(markdown)), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator { id in
            let memo = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
            guard (try? context.fetchCount(memo)) == 1 else {
                app.showToast("找不到原记录", icon: "exclamationmark.circle")
                return
            }
            app.openMemo(id)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let openMemo: @MainActor (UUID) -> Void
        var markdown: String?

        init(openMemo: @escaping @MainActor (UUID) -> Void) { self.openMemo = openMemo }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            if navigationAction.navigationType == .linkActivated, let url {
                if let id = MarkdownHTML.memoLinkID(url) {
                    Task { @MainActor in openMemo(id) }
                } else if MarkdownHTML.isExternalLink(url) {
                    NSWorkspace.shared.open(url)
                }
            }
            let isPreviewLoad = navigationAction.navigationType == .other && url?.absoluteString == "about:blank"
            decisionHandler(isPreviewLoad ? .allow : .cancel)
        }
    }

    private static func page(containing body: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https:">
        <meta name="referrer" content="no-referrer">
        <style>
        :root { color-scheme: light; }
        body { margin: 0; background: #fffdf8; color: #23211d; font: 15px/1.75 -apple-system, sans-serif; }
        main { box-sizing: border-box; max-width: 800px; padding: 20px 24px 60px; margin: 0 auto; overflow-wrap: anywhere; }
        main > :first-child { margin-top: 0; }
        p { margin: 0 0 0.85em; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.3em 0 0.5em; }
        h1 { font-size: 1.9em; }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.2em; }
        ul, ol { padding-left: 1.35em; }
        li > p { margin: 0.24em 0; }
        li:has(> p > input:first-child) { list-style: none; }
        input[type=checkbox] { margin: 0 0.35em 0 -1.3em; accent-color: #0b7650; }
        blockquote { margin: 0 0 1em; padding: 0.15em 0 0.15em 0.85em; border-left: 3px solid #acd0bb; color: #625e54; }
        blockquote > :last-child { margin-bottom: 0; }
        a { color: #0b7650; }
        img { max-width: 100%; height: auto; }
        code { font-family: ui-monospace, Menlo, monospace; background: #f1efe9; padding: 0.12em 0.28em; border-radius: 4px; font-size: 0.9em; }
        pre { background: #f1efe9; padding: 0.9em; border-radius: 8px; overflow: auto; line-height: 1.55; }
        pre code { padding: 0; }
        table { border-collapse: collapse; max-width: 100%; margin: 0 0 1em; }
        th, td { border: 1px solid #e3e0d7; padding: 0.3em 0.65em; text-align: left; }
        th { background: #f1efe9; }
        .right { text-align: right; }
        .center { text-align: center; }
        hr { border: 0; border-top: 1px solid #e3e0d7; margin: 1.5em 0; }
        </style>
        </head>
        <body><main>\(body)</main></body>
        </html>
        """
    }
}
