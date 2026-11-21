import Foundation

/// The full article for a feed item that carries only a summary, like
/// Reeder's and NetNewsWire's reader: fetch the page once, pull out the main
/// text with `Readable` (the library's extractor, Markdown out), keep it in
/// the feed's file. Paced per site by HostGate; off in demo mode.
enum ArticleText {
    static func fetch(_ link: String) async -> String? {
        guard !Demo.isOn, let url = URL(string: link), let host = url.host() else { return nil }
        guard await HostGate.shared.admit(host) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              (http.value(forHTTPHeaderField: "Content-Type") ?? "text/html").contains("html") else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard let capture = Readable.extract(html: html, url: link, site: host.replacingOccurrences(of: "www.", with: "")) else { return nil }
        return FeedParser.Text.cap(capture.text)
    }
}

extension FeedStore {
    /// Drops item text that is a "turn on JavaScript" shell or a code dump
    /// (`ShellText.isJunk`). Returns how many items it cleared.
    static func clearJunk(_ feedID: String) -> Int {
        var entries = entries(feedID)
        var n = 0
        for i in entries.indices {
            if let c = entries[i].content, ShellText.isJunk(c) { entries[i].content = nil; n += 1 }
            if ShellText.isJunk(entries[i].summary) { entries[i].summary = ""; n += 1 }
        }
        guard n > 0 else { return 0 }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        if let data = try? e.encode(entries) { try? data.write(to: folder.appending(path: "\(feedID).json"), options: .atomic) }
        return n
    }

    /// Saves the full text of one item in its feed's file.
    static func setContent(_ content: String, url: String, feedID: String) {
        var entries = entries(feedID)
        guard let i = entries.firstIndex(where: { $0.url == url }), entries[i].content == nil else { return }
        entries[i].content = content
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        if let data = try? e.encode(entries) { try? data.write(to: folder.appending(path: "\(feedID).json"), options: .atomic) }
    }
}
