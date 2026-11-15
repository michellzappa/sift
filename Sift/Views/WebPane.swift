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
    /// Demo mode opens the saved text: pages do not load there. A video or
    /// reel with a transcript opens on its transcript too.
    @State private var reader = false

    var body: some View {
        let a = model.assignment(for: tab)
        content(a)
            .onAppear { reader = opensInReader; model.setSeen([tab.url], true) }
            .onChange(of: tab.url) { reader = opensInReader; model.setSeen([tab.url], true) }
            .onChange(of: reader) { _, on in if on { page.stop() } }
    }

    private var hasTranscript: Bool { model.library[tab.url]?.transcript == true }
    private var hasText: Bool {
        let e = model.library[tab.url]
        return e?.status == "ok" || e?.status == "thin" || e?.transcript == true
    }
    private var opensInReader: Bool { Demo.isOn || (hasTranscript && Library.text(for: tab.url) != nil) }

    @ViewBuilder
    private func content(_ a: Assignment?) -> some View {
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
                if hasText {
                    Toggle(isOn: $reader) { Image(systemName: hasTranscript ? "captions.bubble" : "doc.plaintext") }
                        .toggleStyle(.button)
                        .help(hasTranscript ? "Transcript: what the video says, as text. Turn off to watch." : "Reader: the text Sift captured into your library")
                }
                Button {
                    let p = model.previews[tab.url]
                    model.exportMessage = TabActions.addToReadingList(tab.url, title: model.archiveRecord(for: tab.url)?.title ?? tab.displayTitle, preview: p?.text ?? "")
                } label: { Image(systemName: "eyeglasses") }
                    .help("Add to Safari's Reading List")
                Button { TabActions.openInSafari(page.url?.absoluteString ?? tab.url) } label: { Image(systemName: "safari") }
                    .help("Open in Safari")
                if let onClose {
                    Button { page.stop(); onClose() } label: { Image(systemName: "sidebar.right") }.help("Close the browser")
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 7)

            if a != nil {
                HStack(spacing: 8) {
                    Spacer(minLength: 4)
                    SendButton(tab: tab)
                        .menuStyle(.borderlessButton).fixedSize()
                        .font(.caption)
                }
                .padding(.horizontal, 10).padding(.bottom, 7)
            }

            if reader, let text = Library.text(for: tab.url) {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.archiveRecord(for: tab.url)?.title ?? tab.displayTitle).font(.title2.weight(.semibold))
                        if let e = model.library[tab.url] {
                            Text("\(e.words) words · captured \(e.captured.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, block in
                            ReaderBlock(block: block)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(24)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else if let post = model.xConnected ? model.xPost(for: tab.url) : nil {
                // X posts render natively when the X API is connected.
                Divider()
                ScrollView {
                    XPostView(post: post, quoted: post.quotedID.flatMap { model.xPosts[$0] })
                        .frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                .task(id: tab.url) { await model.refreshXPosts(urls: [tab.url]) }
            } else if Demo.isOn {
                Divider()
                ContentUnavailableView("Pages do not load in demo mode", systemImage: "wifi.slash",
                                       description: Text("The demo uses sample data and never goes online."))
            } else {
                if page.isLoading {
                    ProgressView(value: page.progress).progressViewStyle(.linear).frame(height: 2)
                } else {
                    Divider()
                }
                WebViewHost(webView: page.webView)
                    .onAppear { page.load(tab.url) }
                    .onDisappear { page.stop() }
                    .onChange(of: tab.url) { page.load(tab.url) }
                    .task(id: tab.url) { if model.xConnected, XClient.statusID(tab.url) != nil { await model.refreshXPosts(urls: [tab.url]) } }
            }
        }
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

    /// Stops sound and video at once and unloads the page. Called when the
    /// pane closes or the browser view goes away (reader on, another view):
    /// a WKWebView keeps playing until it is deallocated.
    func stop() {
        webView.pauseAllMediaPlayback()
        webView.closeAllMediaPresentations()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        loaded = nil
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

/// One paragraph of captured Markdown: headings, quotes and list items get
/// their own style; inline Markdown (links, emphasis) renders natively.
private struct ReaderBlock: View {
    let block: String

    var body: some View {
        let line = block.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4)))).font(.headline).padding(.top, 6)
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3)))).font(.title3.weight(.semibold)).padding(.top, 8)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2)))).font(.title2.weight(.semibold)).padding(.top, 8)
        } else if line.hasPrefix("> ") {
            Text(inline(String(line.dropFirst(2)))).italic().foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
        } else {
            Text(inline(line)).font(.body).lineSpacing(3)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
