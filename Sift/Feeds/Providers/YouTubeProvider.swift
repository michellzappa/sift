import Foundation

/// YouTube channels (any address form, or @handle with youtube) and
/// playlists. YouTube still serves a feed per channel and per playlist.
struct YouTubeProvider: FeedProvider {
    let id = "youtube"
    let name = "YouTube"
    let symbol = "play.rectangle"
    let examples = ["youtube.com/@channel", "youtube.com/playlist?list=…"]

    func matches(_ input: String) -> Bool {
        guard let h = FeedInput.host(input) else { return false }
        return h.hasSuffix("youtube.com") || h == "youtu.be"
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        guard let url = FeedInput.url(input) else { return [] }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let list = items.first(where: { $0.name == "list" })?.value {
            return [FeedCandidate(url: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(list)")]
        }
        let parts = FeedInput.path(input)
        if parts.first == "channel", parts.count > 1 {
            return [FeedCandidate(url: "https://www.youtube.com/feeds/videos.xml?channel_id=\(parts[1])")]
        }
        // A handle, /c/, /user/ or a video page: read the channel from the
        // page. In the EU YouTube first redirects to its consent page; the
        // standard consent cookie skips it (no account, no tracking choice).
        guard await HostGate.shared.admit("youtube.com") else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("SOCS=CAI; CONSENT=YES+cb", forHTTPHeaderField: "Cookie")
        req.httpShouldHandleCookies = false
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        let html = String(decoding: data.prefix(1_500_000), as: UTF8.self)
        // The page's own feed link names the right channel; other channelId
        // fields on the page can belong to recommended channels.
        for pattern in [#"feeds/videos\.xml\?channel_id=(UC[\w-]{22})"#, #""externalId":"(UC[\w-]{22})""#,
                        #""channelId":"(UC[\w-]{22})""#, #"/channel/(UC[\w-]{22})"#] {
            if let r = html.range(of: pattern, options: .regularExpression),
               let id = html[r].range(of: #"UC[\w-]{22}"#, options: .regularExpression) {
                return [FeedCandidate(url: "https://www.youtube.com/feeds/videos.xml?channel_id=\(html[id])")]
            }
        }
        return []
    }
}
