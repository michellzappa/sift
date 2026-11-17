import Foundation

/// Your Graph (owner, 2026-11-17: "let the user build their own social
/// graph … show the algorithm, treat users as intelligent creatures").
/// The people, channels, sites and communities behind what you saved, with
/// the numbers that rank them. Sift only proposes: nothing reaches Today
/// until you follow a creator, and a hidden creator stays hidden. Local:
/// built from the library, the archive and the theme assignments, with no
/// network call.

/// One link you saved from a creator.
struct CreatorSave: Hashable, Sendable {
    var url: String
    var title: String
    var date: Date
    var theme: String?
}

struct CreatorTheme: Hashable, Sendable {
    var name: String
    var count: Int
}

struct Creator: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case video, writing, community, code

        var label: String {
            switch self {
            case .video: "Video"
            case .writing: "Writing"
            case .community: "Communities"
            case .code: "Code"
            }
        }

        var symbol: String {
            switch self {
            case .video: "play.rectangle"
            case .writing: "doc.text"
            case .community: "bubble.left.and.bubble.right"
            case .code: "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    /// "youtube:dwarkesh patel", "site:stratechery.com", "reddit:r/swift",
    /// "github:apple/swift". Stable: hidden and followed marks use it.
    var id: String
    var kind: Kind
    var name: String
    /// What Follow takes: a saved video's address (the YouTube provider
    /// reads the channel from it), a host, r/name or owner/repo.
    var input: String
    /// Newest first.
    var saves: [CreatorSave]
    /// Themes of the saves, most first.
    var themes: [CreatorTheme]
    /// Saves weighted by age (`Creators.weight`).
    var score: Double
    /// Saves in the last 90 days.
    var recent: Int
    /// The followed feed, when you follow this creator.
    var feedID: String?

    var count: Int { saves.count }
    var lastSaved: Date? { saves.first?.date }
}

enum Creators {
    /// A save counts half after this many days, a quarter after twice that.
    static let halfLifeDays = 90.0
    /// Saves a creator needs before Sift shows it.
    static let minSaves = 2
    static let maxShown = 400

    static func weight(_ date: Date, now: Date = Date()) -> Double {
        pow(0.5, max(0, now.timeIntervalSince(date)) / 86_400 / halfLifeDays)
    }

    /// A link as the graph sees it.
    struct Link {
        var url: String
        var title: String
        var date: Date
        var theme: String?
        /// The library's author (YouTube channel), when known.
        var author: String?
    }

    /// The creator a link belongs to, if Sift can follow it: a YouTube
    /// channel (by the library's author), a subreddit, a GitHub repository,
    /// a Medium or Substack writer, or a site.
    static func key(_ link: Link) -> (id: String, kind: Creator.Kind, name: String, input: String)? {
        guard let u = URL(string: link.url), let h = u.host()?.lowercased() else { return nil }
        let host = h.replacingOccurrences(of: #"^(www\.|m\.|old\.)"#, with: "", options: .regularExpression)
        let parts = u.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("youtube.com") || host == "youtu.be" {
            guard let name = link.author?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  TranscriptTool.videoID(link.url) != nil else { return nil }
            return ("youtube:" + name.lowercased(), .video, name, link.url)
        }
        if host.hasSuffix("reddit.com"), parts.count >= 2, parts[0] == "r" {
            let sub = "r/" + parts[1].lowercased()
            return ("reddit:" + sub, .community, sub, sub)
        }
        if host == "github.com", parts.count >= 2,
           !["orgs", "settings", "notifications", "search", "topics", "features", "marketplace"].contains(parts[0]) {
            let repo = "\(parts[0])/\(parts[1])"
            return ("github:" + repo.lowercased(), .code, repo, repo)
        }
        if host.hasSuffix("medium.com"), let at = parts.first, at.hasPrefix("@") {
            return ("site:medium.com/" + at.lowercased(), .writing, at, "https://medium.com/\(at)")
        }
        if FeedSuggestions.skipHosts.contains(host) || FeedSuggestions.skipHosts.contains(where: { host.hasSuffix("." + $0) }) {
            return nil
        }
        return ("site:" + host, .writing, host, host)
    }

    /// Every creator with `minSaves` or more, best score first. `followed`
    /// maps a creator id to the feed that follows it.
    static func build(_ links: [Link], followed: [String: String], now: Date = Date()) -> [Creator] {
        var groups: [String: (kind: Creator.Kind, name: String, input: String, saves: [CreatorSave])] = [:]
        for link in links {
            guard let k = key(link) else { continue }
            let save = CreatorSave(url: link.url, title: link.title, date: link.date, theme: link.theme)
            if groups[k.id] == nil { groups[k.id] = (k.kind, k.name, k.input, []) }
            groups[k.id]!.saves.append(save)
        }
        let recentCutoff = now.addingTimeInterval(-90 * 86_400)
        var out: [Creator] = []
        for (id, g) in groups where g.saves.count >= minSaves {
            let saves = g.saves.sorted { $0.date > $1.date }
            var counts: [String: Int] = [:]
            for t in saves.compactMap(\.theme) { counts[t, default: 0] += 1 }
            let themes: [CreatorTheme] = counts.map { CreatorTheme(name: $0.key, count: $0.value) }
                .sorted { a, b in a.count == b.count ? a.name < b.name : a.count > b.count }
            var score = 0.0
            for save in saves { score += weight(save.date, now: now) }
            let recent = saves.filter { $0.date >= recentCutoff }.count
            let input = g.kind == .video ? saves[0].url : g.input
            out.append(Creator(id: id, kind: g.kind, name: g.name, input: input, saves: saves, themes: themes,
                               score: score, recent: recent, feedID: followed[id]))
        }
        return Array(out.sorted { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }.prefix(maxShown))
    }

    /// Which creator each followed feed belongs to: the creator it was
    /// followed from, else a match by channel name (YouTube), host,
    /// subreddit or repository.
    static func followed(_ feeds: [Feed]) -> [String: String] {
        var out: [String: String] = [:]
        for f in feeds {
            if let c = f.creator { out[c] = f.id; continue }
            if f.provider == "youtube" || f.url.contains("youtube.com/feeds") {
                if !f.url.contains("playlist_id") { out["youtube:" + f.title.lowercased()] = f.id }
                continue
            }
            for raw in [f.site, f.url].compactMap({ $0 }) {
                guard let input = AppModel.followInput(forLink: raw)?.lowercased() else { continue }
                if input.hasPrefix("r/") { out["reddit:" + input] = f.id }
                else if raw.contains("github.com"), input.contains("/") { out["github:" + input] = f.id }
                else if !input.hasPrefix("http") { out["site:" + input] = f.id }
            }
        }
        return out
    }
}
