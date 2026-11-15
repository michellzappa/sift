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
        // A handle, /c/, /user/ or a video page: read the channel id from the page.
        guard await HostGate.shared.admit("youtube.com"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        let html = String(decoding: data.prefix(1_500_000), as: UTF8.self)
        for pattern in [#""channelId":"(UC[\w-]{22})""#, #"channel_id=(UC[\w-]{22})"#, #"/channel/(UC[\w-]{22})"#] {
            if let r = html.range(of: pattern, options: .regularExpression),
               let id = html[r].range(of: #"UC[\w-]{22}"#, options: .regularExpression) {
                return [FeedCandidate(url: "https://www.youtube.com/feeds/videos.xml?channel_id=\(html[id])")]
            }
        }
        return []
    }
}
