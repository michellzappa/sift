import Foundation

// Today, themes first (ADR 0001, decisions 7 and 8; issue #41): Today is
// grouped by theme, and each item carries a small badge for its network.
// Compiled into the Mac app and the phone (prototypes/ios-deck/project.yml):
// keep it Foundation only.

/// The network a link comes from (the badge): YouTube, Instagram, TikTok, X, Bluesky,
/// Mastodon, Reddit and so on, else the web. The badge on Today's rows and
/// cards. Names follow `Place.names` (Feeds/People.swift). Not the dial
/// group: `Network` (Engine/NetworkDial.swift) groups feeds for the network
/// dials and maps a link through this one table (`Network.of(url:)`).
struct LinkNetwork: Hashable, Sendable {
    /// youtube, instagram, tiktok, x, bluesky, mastodon, reddit, hackernews,
    /// github, substack, medium, tumblr, podcast, arxiv, news or web.
    var id: String
    var name: String
    var symbol: String

    /// Hosts that name the network by themselves.
    private static let hosts: [(String, String)] = [
        ("youtube.com", "youtube"), ("youtu.be", "youtube"), ("instagram.com", "instagram"),
        ("tiktok.com", "tiktok"), ("x.com", "x"), ("twitter.com", "x"), ("bsky.app", "bluesky"),
        ("reddit.com", "reddit"), ("news.ycombinator.com", "hackernews"), ("github.com", "github"),
        ("substack.com", "substack"), ("medium.com", "medium"), ("tumblr.com", "tumblr"),
        ("arxiv.org", "arxiv"), ("news.google.com", "news"), ("threads.com", "threads"), ("threads.net", "threads"),
    ]

    private static let names: [String: String] = [
        "youtube": "YouTube", "instagram": "Instagram", "tiktok": "TikTok", "x": "X", "bluesky": "Bluesky",
        "mastodon": "Mastodon", "reddit": "Reddit", "hackernews": "Hacker News", "github": "GitHub",
        "substack": "Substack", "medium": "Medium", "tumblr": "Tumblr", "podcast": "Podcast", "arxiv": "arXiv",
        "news": "News", "threads": "Threads", "web": "Web",
    ]

    private static func symbol(_ id: String) -> String {
        switch id {
        case "youtube": "play.rectangle"
        case "instagram": "camera"
        case "tiktok": "music.note"
        case "x", "bluesky", "mastodon", "threads": "bubble.left"
        case "reddit", "hackernews": "bubble.left.and.bubble.right"
        case "github": "chevron.left.forwardslash.chevron.right"
        case "substack", "medium": "envelope"
        case "podcast": "mic"
        case "arxiv": "doc.text"
        case "news": "newspaper"
        default: "globe"
        }
    }

    init(id: String) {
        self.id = id
        name = Self.names[id] ?? id.capitalized
        symbol = Self.symbol(id)
    }

    /// The network of a link: its host first (a YouTube video in a blog's
    /// feed is YouTube), then the feed's provider id, then a Mastodon status
    /// address (/@user/123), else the web.
    static func of(url: String, provider: String? = nil) -> LinkNetwork {
        let host = (URL(string: url)?.host() ?? "").lowercased()
        if let id = hosts.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) })?.1 { return LinkNetwork(id: id) }
        if let provider, provider != "web", names[provider] != nil { return LinkNetwork(id: provider) }
        if url.range(of: #"^https://[^/]+/@[\w.]+/\d+"#, options: .regularExpression) != nil { return LinkNetwork(id: "mastodon") }
        return LinkNetwork(id: "web")
    }
}

/// Today's picks in theme sections.
enum TodayThemes {
    /// The section for picks without a theme. It is always last.
    static let other = "Other"

    struct Group<T> {
        /// Nil for the "Other" section.
        var theme: String?
        var items: [T]
        var title: String { theme ?? TodayThemes.other }
    }

    /// Groups items by theme. Sections go by their best item's score, high
    /// first (a section without scores goes by where its first item was);
    /// "Other" goes last. Inside a section the items keep their order (the
    /// rank order Today gives).
    static func group<T>(_ items: [T], theme: (T) -> String?, score: (T) -> Double?) -> [Group<T>] {
        var order: [String] = []
        var byTheme: [String: [T]] = [:]
        var best: [String: Double] = [:]
        var others: [T] = []
        for item in items {
            guard let t = theme(item), !t.isEmpty else { others.append(item); continue }
            if byTheme[t] == nil { order.append(t) }
            byTheme[t, default: []].append(item)
            if let s = score(item) { best[t] = max(best[t] ?? -.infinity, s) }
        }
        let first = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let sorted = order.sorted { a, b in
            let sa = best[a] ?? -.infinity, sb = best[b] ?? -.infinity
            return sa != sb ? sa > sb : first[a]! < first[b]!
        }
        var sections = sorted.map { Group(theme: $0, items: byTheme[$0] ?? []) }
        if !others.isEmpty { sections.append(Group(theme: nil, items: others)) }
        return sections
    }
}
