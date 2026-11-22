import Foundation

// Network dials (owner, ADR 0001 decision 6; issue #40). Each network that
// brings items into Today has one dial: More, Normal, Less or Off. Next to
// the dial, Sift shows what it learned from use (opens, keeps, skips per
// network, from the signals files). This file is the one list of networks
// and dials. It is Foundation only: the phone compiles it too
// (prototypes/ios-deck/project.yml).

/// Where a Today pick comes from, by its feed's provider
/// (`Feed.provider`, else `AppModel.providerID(forFeed:)`).
enum Network: String, CaseIterable, Codable, Sendable, Identifiable {
    case youtube, podcasts, bluesky, mastodon, reddit, hackernews, blogs, news, github, arxiv
    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: "YouTube"
        case .podcasts: "Podcasts"
        case .bluesky: "Bluesky"
        case .mastodon: "Mastodon"
        case .reddit: "Reddit"
        case .hackernews: "Hacker News"
        case .blogs: "Blogs and newsletters"
        case .news: "Google News"
        case .github: "GitHub"
        case .arxiv: "arXiv"
        }
    }

    var symbol: String {
        switch self {
        case .youtube: "play.rectangle"
        case .podcasts: "mic"
        case .bluesky, .mastodon: "bubble.left"
        case .reddit: "bubble.left.and.bubble.right"
        case .hackernews: "flame"
        case .blogs: "doc.text"
        case .news: "newspaper"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .arxiv: "graduationcap"
        }
    }

    /// The network of a feed provider id. Web, Substack, Medium, Tumblr and
    /// an unknown provider are blogs and newsletters.
    static func of(provider: String?) -> Network {
        switch provider {
        case "youtube": .youtube
        case "podcast": .podcasts
        case "bluesky": .bluesky
        case "mastodon": .mastodon
        case "reddit": .reddit
        case "hackernews": .hackernews
        case "news": .news
        case "github": .github
        case "arxiv": .arxiv
        default: .blogs
        }
    }

    /// The network of a link that no feed carries ("Linked by" picks), by host.
    static func of(url: String) -> Network {
        let host = (URL(string: url)?.host() ?? "").lowercased()
        let rules: [(String, Network)] = [("youtube.com", .youtube), ("youtu.be", .youtube), ("reddit.com", .reddit),
                                          ("news.ycombinator.com", .hackernews), ("bsky.app", .bluesky),
                                          ("github.com", .github), ("arxiv.org", .arxiv), ("news.google.com", .news)]
        return rules.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1 ?? .blogs
    }
}

/// How much of Today one network gets.
enum NetworkDial: String, CaseIterable, Codable, Sendable, Identifiable {
    case more, normal, less, off
    var id: String { rawValue }

    var title: String {
        switch self {
        case .more: "More"
        case .normal: "Normal"
        case .less: "Less"
        case .off: "Off"
        }
    }

    var help: String {
        switch self {
        case .more: "Score × 1.5, and each feed has up to \(NetworkDial.morePerFeed) unseen items in Today."
        case .normal: "As it is."
        case .less: "Score × 0.5, 1 unseen item per feed, and no extra slots."
        case .off: "No picks from this network."
        }
    }

    /// The factor on the score that the dial sets.
    var factor: Double {
        switch self {
        case .more: 1.5
        case .normal: 1
        case .less: 0.5
        case .off: 0
        }
    }

    /// Unseen items one Normal feed of a More network may have in Today.
    static let morePerFeed = 5
    /// What the learned term can add or take: factor × (1 + 0.3 × learned).
    static let learnedWeight = 0.3

    init(_ raw: String?) { self = raw.flatMap(NetworkDial.init(rawValue:)) ?? .normal }
}

/// What Sift learned from use for one network, over the last
/// `NetworkStats.days` days of signals (this Mac and every phone).
struct NetworkStats: Codable, Hashable, Sendable {
    /// Picks you saw: items with any signal, and seen picks in Today.
    var shown: Int
    var opened: Int
    var kept: Int
    var skipped: Int
    /// -1…1: how much more (or less) you do with this network than with
    /// the others. Zero until `minShown` picks.
    var learned: Double

    static let days: Double = 30
    static let minShown = 5

    var openShare: Double { shown == 0 ? 0 : Double(opened) / Double(shown) }
    var keepShare: Double { shown == 0 ? 0 : Double(kept) / Double(shown) }

    /// "You open 40% of the YouTube picks you see and keep 8%."
    func summary(_ network: Network) -> String {
        if shown < Self.minShown { return shown == 0 ? "Still learning: no \(network.title) picks seen yet" : "Still learning: \(shown) picks seen" }
        let open = Int((openShare * 100).rounded()), keep = Int((keepShare * 100).rounded())
        var s = "You open \(open)% of the \(network.title) picks you see and keep \(keep)%"
        if skipped > 0 { s += ", skip \(skipped)" }
        return s + "."
    }

    /// "Sift lifts it a little" and the like.
    var learnedText: String {
        switch learned {
        case let l where l > 0.3: "Sift lifts it (× \(String(format: "%.2f", 1 + NetworkDial.learnedWeight * learned)))"
        case let l where l > 0.05: "Sift lifts it a little (× \(String(format: "%.2f", 1 + NetworkDial.learnedWeight * learned)))"
        case let l where l < -0.3: "Sift lowers it (× \(String(format: "%.2f", 1 + NetworkDial.learnedWeight * learned)))"
        case let l where l < -0.05: "Sift lowers it a little (× \(String(format: "%.2f", 1 + NetworkDial.learnedWeight * learned)))"
        default: "No lean either way"
        }
    }

    static let empty = NetworkStats(shown: 0, opened: 0, kept: 0, skipped: 0, learned: 0)
}
