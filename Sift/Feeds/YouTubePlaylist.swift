import Foundation

/// A public or unlisted YouTube playlist as a "to watch" list. YouTube's
/// playlist feed (`feeds/videos.xml?playlist_id=`) holds only the first 15
/// videos in playlist order, so videos added at the end of a longer list
/// never reach it. Sift also reads the playlist page (no login, the same
/// consent cookie as the channel lookup), which lists the first 100.
///
/// Dates: a playlist item's date is when Sift first saw it in the list,
/// not when YouTube published the video, so a video you add today counts
/// as new in Today. On the first read (nothing stored yet) items keep the
/// feed's publish date, and items only on the page have none, so an old
/// backlog does not fill Today.
enum YouTubePlaylist {
    /// The playlist id in a YouTube feed address, else nil.
    static func id(inFeed url: URL) -> String? {
        guard let host = url.host()?.lowercased(), host.hasSuffix("youtube.com") else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let id = items.first(where: { $0.name == "playlist_id" })?.value, !id.isEmpty else { return nil }
        return id
    }

    /// The feed's items plus the videos only on the playlist page, with
    /// dates set as described above. `stored` is what Sift already holds for
    /// this feed (empty when following).
    static func complete(_ parsed: FeedParser.Parsed, list: String, stored: [FeedEntry]) async -> FeedParser.Parsed {
        var out = parsed
        let known = Set(parsed.entries.map(\.url))
        if let page = await pageEntries(list) {
            out.entries += page.filter { !known.contains($0.url) }
        }
        guard !stored.isEmpty else { return out }
        let firstSeen = Dictionary(stored.map { ($0.url, $0.date) }, uniquingKeysWith: { a, _ in a })
        let now = Date()
        for i in out.entries.indices {
            if let date = firstSeen[out.entries[i].url] { out.entries[i].date = date } else { out.entries[i].date = now }
        }
        return out
    }

    /// The first 100 videos on the playlist page. Nil when the page could
    /// not be read (private playlist, consent or check page, throttling).
    static func pageEntries(_ list: String) async -> [FeedEntry]? {
        guard let url = URL(string: "https://www.youtube.com/playlist?list=\(list)"),
              await HostGate.shared.admit("youtube.com") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("SOCS=CAI; CONSENT=YES+cb", forHTTPHeaderField: "Cookie")
        req.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 || code == 503 { await HostGate.shared.pause("youtube.com", seconds: 3600); return nil }
        guard code == 200 else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard let start = html.range(of: "var ytInitialData = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8)) else { return nil }
        var out: [FeedEntry] = []
        var seen = Set<String>()
        collect(json) { lockup in
            guard lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
                  let id = lockup["contentId"] as? String, seen.insert(id).inserted else { return }
            let meta = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
            let title = ((meta?["title"] as? [String: Any])?["content"] as? String) ?? ""
            out.append(FeedEntry(url: "https://www.youtube.com/watch?v=\(id)", title: title, date: nil,
                                 author: channel(meta), summary: "",
                                 image: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"))
        }
        return out
    }

    /// Calls `found` for every `lockupViewModel` in the page data, in order.
    private static func collect(_ node: Any, _ found: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            if let lockup = dict["lockupViewModel"] as? [String: Any] { found(lockup); return }
            for key in dict.keys.sorted() where key != "frameworkUpdates" { collect(dict[key]!, found) }
        } else if let list = node as? [Any] {
            for item in list { collect(item, found) }
        }
    }

    /// The first text in the first metadata row: the channel name.
    private static func channel(_ meta: [String: Any]?) -> String? {
        let rows = ((meta?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]]
        let part = (rows?.first?["metadataParts"] as? [[String: Any]])?.first
        let text = (part?["text"] as? [String: Any])?["content"] as? String
        return (text?.isEmpty ?? true) ? nil : text
    }
}
