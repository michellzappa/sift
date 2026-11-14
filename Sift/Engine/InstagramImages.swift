import CryptoKit
import Foundation
import WebKit

/// Gets the image of a public Instagram post from Instagram's own public
/// embed (the one websites use), loaded in a hidden web view: the embed only
/// fills in its image once its JavaScript runs. No login, no other identity.
/// The image is saved on this Mac, because Instagram's image links expire.
@MainActor
final class InstagramImageFetcher: NSObject, WKNavigationDelegate {
    private let web: WKWebView
    private var finished: CheckedContinuation<Void, Never>?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 540, height: 900), configuration: config)
        super.init()
        web.navigationDelegate = self
    }

    static var folder: URL {
        let dir = StateFile.url.deletingLastPathComponent().appending(path: "Images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Returns a file URL of the saved image, or nil (private, deleted, or
    /// the embed changed).
    func image(for postURL: String) async -> String? {
        guard let r = postURL.range(of: #"instagram\.com/(p|reel|tv)/[^/?#]+"#, options: .regularExpression),
              let embed = URL(string: "https://www." + postURL[r] + "/embed/captioned/")
        else { return nil }
        let file = Self.folder.appending(path: Insecure.SHA1.hash(data: Data(postURL.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16) + ".jpg")
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { return file.absoluteString }

        web.load(URLRequest(url: embed, timeoutInterval: 20))
        await withCheckedContinuation { c in finished = c }
        // The embed's script swaps in the image shortly after load.
        var src: String?
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(500))
            let js = "(document.querySelector('img.EmbeddedMediaImage') || {}).src || ''"
            if let s = try? await web.evaluateJavaScript(js) as? String, s.hasPrefix("https://") { src = s; break }
        }
        guard let src, let url = URL(string: src),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000
        else { return nil }
        try? data.write(to: file, options: .atomic)
        return file.absoluteString
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finished?.resume(); self.finished = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finished?.resume(); self.finished = nil }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finished?.resume(); self.finished = nil }
    }
}
