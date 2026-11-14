import SwiftUI
import WebKit

/// The right-hand browser: shows a link in place, so you can read it without
/// leaving Sift. A small header carries what Sift knows about the link (theme,
/// use, next action), and a toolbar has back, forward, reload and Open in
/// Safari. Pages share one website data store, so a site you sign in to here
/// stays signed in.
struct WebPane: View {
    @Environment(AppModel.self) private var model
    let tab: SafariTab
    var onClose: (() -> Void)?
    @State private var page = WebPage()

    var body: some View {
        let a = model.assignment(for: tab)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { page.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!page.canGoBack)
                Button { page.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!page.canGoForward)
                Button { page.webView.reload() } label: { Image(systemName: page.isLoading ? "xmark" : "arrow.clockwise") }
                Text(page.url?.host() ?? tab.host)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                Button { TabActions.openInSafari(page.url?.absoluteString ?? tab.url) } label: { Image(systemName: "safari") }
                    .help("Open in Safari")
                if let onClose {
                    Button(action: onClose) { Image(systemName: "sidebar.right") }.help("Close the browser")
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 7)

            if a != nil {
                HStack(spacing: 8) {
                    if let use = a?.use, !use.isEmpty {
                        Text(use).font(.caption).foregroundStyle(.tint).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        ForEach(NextAction.allCases, id: \.self) { action in
                            Button { model.setAction(action, for: tab) } label: { Label(action.label, systemImage: action.symbol) }
                        }
                    } label: {
                        Label(a?.action?.label ?? "Next action", systemImage: a?.action?.symbol ?? "arrow.forward.circle")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(.caption)
                }
                .padding(.horizontal, 10).padding(.bottom, 7)
            }

            if page.isLoading {
                ProgressView(value: page.progress).progressViewStyle(.linear).frame(height: 2)
            } else {
                Divider()
            }
            WebViewHost(webView: page.webView)
        }
        .onAppear { page.load(tab.url) }
        .onChange(of: tab.url) { page.load(tab.url) }
    }
}

/// Owns one WKWebView and mirrors its state for SwiftUI.
@MainActor
@Observable
final class WebPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var progress = 0.0
    var url: URL?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var loaded: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = nil
        super.init()
        webView.navigationDelegate = self
        observers = [
            webView.observe(\.canGoBack) { [weak self] v, _ in MainActor.assumeIsolated { self?.canGoBack = v.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] v, _ in MainActor.assumeIsolated { self?.canGoForward = v.canGoForward } },
            webView.observe(\.isLoading) { [weak self] v, _ in MainActor.assumeIsolated { self?.isLoading = v.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] v, _ in MainActor.assumeIsolated { self?.progress = v.estimatedProgress } },
            webView.observe(\.url) { [weak self] v, _ in MainActor.assumeIsolated { self?.url = v.url } },
        ]
    }

    func load(_ string: String) {
        guard string != loaded, let url = URL(string: string) else { return }
        loaded = string
        webView.load(URLRequest(url: url))
    }

    /// Links that ask for a new window open in the same pane.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.targetFrame == nil, let url = action.request.url {
            webView.load(URLRequest(url: url))
            return .cancel
        }
        return .allow
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
