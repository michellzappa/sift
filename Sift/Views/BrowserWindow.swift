import SwiftUI

/// Sift's own browser window. Originals open here, not in Safari: a page
/// opened in Safari becomes a tab, and tabs come back into Sift as links.
/// One window; a new page replaces the current one. Open in Safari stays an
/// explicit button.
enum BrowserWindow {
    static let id = "browser"
}

struct BrowserWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var page = WebPage()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { page.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!page.canGoBack)
                Button { page.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!page.canGoForward)
                Button { page.webView.reload() } label: { Image(systemName: page.isLoading ? "xmark" : "arrow.clockwise") }
                Text(page.url?.host() ?? model.browserURL?.host() ?? "")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                Button { if let u = page.url ?? model.browserURL { model.copy(u.absoluteString) } } label: { Image(systemName: "link") }
                    .help("Copy the link")
                Button { TabActions.openInSafari((page.url ?? model.browserURL)?.absoluteString ?? "") } label: { Image(systemName: "safari") }
                    .help("Open in Safari (it becomes a Safari tab)")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 8)
            if page.isLoading {
                ProgressView(value: page.progress).progressViewStyle(.linear).frame(height: 2)
            } else {
                Divider()
            }
            WebViewHost(webView: page.webView)
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { if let u = model.browserURL { page.load(u.absoluteString) } }
        .onChange(of: model.browserURL) { _, u in if let u { page.load(u.absoluteString) } }
        .onDisappear { page.stop() }
    }
}
