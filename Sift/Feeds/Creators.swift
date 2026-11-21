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
    /// False for X, Instagram and TikTok authors: Sift shows them, but
    /// they have no feed to follow.
    var hasFeed: Bool { Creators.hasFeed(id) }
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

    /// Creator ids on platforms without feeds (X, Instagram, TikTok). The
    /// part after the prefix matches `Place.id`, so People can join them.
    static let noFeedPrefixes = ["x:", "instagram:", "tiktok:"]
    static func hasFeed(_ id: String) -> Bool { !noFeedPrefixes.contains { id.hasPrefix($0) } }

    private static let titleHandle = try! NSRegularExpression(pattern: #"(?:^@|\(@)([A-Za-z0-9_.]{1,30})\)?$"#)

    /// The handle in a title Sift wrote for a saved post: "Name (@user)" or
    /// "@user" (`InstagramReader`, `AppModel.fetchTikTokDetails`).
    static func handle(inTitle title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespaces)
        let ns = t as NSString
        guard let m = titleHandle.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// The author of an X post, Instagram post or TikTok video, from what
    /// Sift already has: the handle in an X status address, the owner that
    /// Instagram's export names, the author TikTok's page named. No fetch.
    static func socialKey(_ link: Link, host: String, parts: [String]) -> (id: String, kind: Creator.Kind, name: String, input: String)? {
        switch host {
        case "x.com", "twitter.com":
            guard parts.count >= 3, parts[1] == "status", !["i", "home", "search", "intent"].contains(parts[0].lowercased()),
                  parts[0].range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil else { return nil }
            let h = parts[0]
            return ("x:@" + h.lowercased(), .writing, "@" + h, "https://x.com/\(h)")
        case "instagram.com":
            guard let h = handle(inTitle: link.title) ?? handle(inTitle: link.author ?? "") else { return nil }
            return ("instagram:@" + h.lowercased(), .video, "@" + h, "https://www.instagram.com/\(h)/")
        case "tiktok.com":
            let fromURL = parts.first.flatMap { $0.hasPrefix("@") && $0.count > 1 ? String($0.dropFirst()) : nil }
            guard let h = fromURL ?? handle(inTitle: link.title) ?? handle(inTitle: link.author ?? "") else { return nil }
            return ("tiktok:@" + h.lowercased(), .video, "@" + h, "https://www.tiktok.com/@\(h)")
        default:
            return nil
        }
    }

    /// The creator a link belongs to: a YouTube channel (by the library's
    /// author), a subreddit, a GitHub repository, a Medium or Substack
    /// writer, an X, Instagram or TikTok author (no feed), or a site.
    static func key(_ link: Link) -> (id: String, kind: Creator.Kind, name: String, input: String)? {
        guard let u = URL(string: link.url), let h = u.host()?.lowercased() else { return nil }
        let host = h.replacingOccurrences(of: #"^(www\.|m\.|old\.|mobile\.)"#, with: "", options: .regularExpression)
        let parts = u.pathComponents.filter { $0 != "/" }
        if ["x.com", "twitter.com", "instagram.com", "tiktok.com"].contains(host) { return socialKey(link, host: host, parts: parts) }
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
            let input = g.kind == .video && hasFeed(id) ? saves[0].url : g.input
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

// MARK: - Next door

/// One link that points a trusted creator at a neighbour.
struct NeighborEvidence: Hashable, Sendable {
    /// The creator in your graph who linked.
    var from: String
    /// The saved link or feed item that carries the link.
    var item: String
    var itemURL: String
    /// The address it links to.
    var link: String
}

/// A creator next door: not in your graph yet, linked by two or more
/// creators who are (owner, 2026-11-17: "extend the user's reading in the
/// direction of those interest vectors"; first step: "Next door").
struct Neighbor: Identifiable, Hashable, Sendable {
    var id: String
    var kind: Creator.Kind
    var name: String
    var input: String
    /// Creators in your graph who link to it, most links first.
    var linkedBy: [String]
    /// Links to it, over all those creators.
    var mentions: Int
    var score: Double
    var themes: [CreatorTheme]
    var evidence: [NeighborEvidence]
}

/// Next door: the creators your creators link to. Local and free: Sift reads
/// the text it already saved (pages, video descriptions, transcripts) and
/// the items of followed feeds, collects the outbound links, and counts
/// which creators outside your graph two or more of yours point to.
/// Sponsor links, shops, support pages and a creator's own site do not count.
enum NextDoor {
    static let minLinkers = 2
    static let maxShown = 150
    /// Saves and feed items read per creator.
    static let perCreator = 40

    /// Hosts that are platforms, shops, tips, sponsors or link shorteners.
    static let noise: Set<String> = [
        "patreon.com", "spotify.com", "spoti.fi", "discord.gg", "discord.com", "amzn.to", "a.co", "apple.co", "brilliant.org",
        "ground.news", "shopify.com", "nebula.tv", "ko-fi.com", "linktr.ee", "creativecommons.org", "incogni.com", "betterhelp.com",
        "geni.us", "paypal.me", "paypal.com", "saily.com", "tinyurl.com", "penname.co", "skool.com", "fiverr.com", "t.me",
        "joindeleteme.com", "pxf.io", "expressvpn.com", "nordvpn.com", "imdb.com", "doi.org", "archive.org", "wikimedia.org",
        "buymeacoffee.com", "gumroad.com", "eventbrite.com", "calendly.com", "goo.gl", "ow.ly", "lnkd.in", "forms.gle", "zoom.us",
        "notion.so", "typeform.com", "mailchi.mp", "audible.com", "bookshop.org", "goodreads.com", "arxiv.org", "twitch.tv",
        "rumble.com", "snapchat.com", "threads.com", "trib.al", "fb.com", "epidemicsound.com", "cnb.cx", "dropbox.com",
        "amazon.co.uk", "amazon.de", "amazon.ca", "bsky.social", "substack.com", "medium.com", "squarespace.com", "teespring.com",
        "spreadshirt.com", "merch.com", "redbubble.com", "kit.com", "convertkit.com", "beacons.ai", "bio.link", "flowcode.com",
        "dub.sh", "rebrand.ly", "shorturl.at", "is.gd", "buff.ly", "hubs.ly", "hubs.la", "mailchimp.com", "gofundme.com",
    ]

    static let promo = try! NSRegularExpression(pattern: #"[?&](utm_|ref=|code=|aff|promo|via=|coupon|discount)|/(go|lp|deal|offer)/"#, options: .caseInsensitive)
    static let sponsorLine = try! NSRegularExpression(pattern: #"sponsor|thanks to|use code|promo|discount|% off|free trial|sign up|get started|special offer|affiliate|support (the|this) (show|channel)"#, options: .caseInsensitive)
    static let linkPattern = try! NSRegularExpression(pattern: #"https?://[^\s)\]>"'<]+"#)

    /// The creator an outbound link names, if it is one Sift could follow.
    /// YouTube counts only as a channel page (@handle, /channel/…).
    static func key(_ link: String) -> (id: String, kind: Creator.Kind, name: String, input: String)? {
        guard let u = URL(string: link), let h = u.host()?.lowercased() else { return nil }
        let host = h.replacingOccurrences(of: #"^(www\.|m\.|old\.)"#, with: "", options: .regularExpression)
        let parts = u.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("youtube.com") {
            if let at = parts.first, at.hasPrefix("@") { return ("youtube:" + at.lowercased(), .video, at, "https://www.youtube.com/\(at)") }
            if parts.count > 1, parts[0] == "channel" { return ("youtube:" + parts[1].lowercased(), .video, "YouTube channel", "https://www.youtube.com/channel/\(parts[1])") }
            return nil
        }
        if host == "bsky.app", parts.count >= 2, parts[0] == "profile" {
            return ("bluesky:" + parts[1].lowercased(), .writing, "@" + parts[1], "@" + parts[1])
        }
        guard !noise.contains(host), !noise.contains(where: { host.hasSuffix("." + $0) && !host.hasSuffix(".substack.com") && !host.hasSuffix(".medium.com") }) else { return nil }
        // Next Door proposes only creators with a feed.
        guard let k = Creators.key(Creators.Link(url: link, title: "", date: Date(), theme: nil, author: nil)), Creators.hasFeed(k.id) else { return nil }
        return k
    }

    /// True when the target is the creator's own site: "Lex Fridman" and
    /// lexfridman.com, "Every" and every.to, "TED" and ted.com.
    static func isOwn(_ target: String, by creator: String) -> Bool {
        let flat = creator.lowercased().filter { $0.isLetter || $0.isNumber }
        guard let label = target.replacingOccurrences(of: #"^(site:|youtube:@?|bluesky:)"#, with: "", options: .regularExpression)
            .split(separator: ".").first.map(String.init)?.filter({ $0.isLetter || $0.isNumber }), label.count >= 3, flat.count >= 3 else { return false }
        return flat.contains(label) || label.contains(flat)
    }

    /// A creator in your graph and the text Sift has from it.
    struct Source: Sendable {
        var id: String
        var name: String
        var score: Double
        var themes: [String]
        var texts: [(title: String, url: String, text: String)]
    }

    static func build(_ sources: [Source], known: Set<String>) -> [Neighbor] {
        struct Acc { var kind: Creator.Kind; var name: String; var input: String; var by: [String: Int] = [:]; var weight: [String: Double] = [:]
                     var themes: [String: Int] = [:]; var evidence: [NeighborEvidence] = [] }
        var acc: [String: Acc] = [:]
        for src in sources {
            for t in src.texts {
                let own = URL(string: t.url)?.host()?.replacingOccurrences(of: "www.", with: "")
                let ns = t.text as NSString
                var seen = Set<String>()
                for m in linkPattern.matches(in: t.text, range: NSRange(location: 0, length: ns.length)) {
                    let link = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?*_"))
                    guard promo.firstMatch(in: link, range: NSRange(location: 0, length: (link as NSString).length)) == nil,
                          let k = key(link), !known.contains(k.id), k.id != src.id, seen.insert(k.id).inserted,
                          URL(string: link)?.host()?.replacingOccurrences(of: "www.", with: "") != own,
                          !isOwn(k.id, by: src.name) else { continue }
                    let line = ns.lineRange(for: m.range)
                    if sponsorLine.firstMatch(in: t.text, range: line) != nil { continue }
                    if acc[k.id] == nil { acc[k.id] = Acc(kind: k.kind, name: k.name, input: k.input) }
                    acc[k.id]!.by[src.name, default: 0] += 1
                    acc[k.id]!.weight[src.name] = src.score
                    for th in src.themes { acc[k.id]!.themes[th, default: 0] += 1 }
                    if acc[k.id]!.evidence.count < 12 {
                        acc[k.id]!.evidence.append(NeighborEvidence(from: src.name, item: t.title, itemURL: t.url, link: link))
                    }
                }
            }
        }
        var out: [Neighbor] = []
        for (id, a) in acc where a.by.count >= minLinkers {
            // Each creator who links adds 1 + log(1 + its own score), so a
            // link from a creator high in your graph counts more.
            var score = 0.0
            for (_, w) in a.weight { score += 1 + log(1 + w) }
            let linkedBy = a.by.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
            var mentions = 0
            for v in a.by.values { mentions += v }
            let themes = a.themes.map { CreatorTheme(name: $0.key, count: $0.value) }
                .sorted { x, y in x.count == y.count ? x.name < y.name : x.count > y.count }
            out.append(Neighbor(id: id, kind: a.kind, name: a.name, input: a.input, linkedBy: linkedBy, mentions: mentions,
                                score: score, themes: themes, evidence: a.evidence))
        }
        return Array(out.sorted { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }.prefix(maxShown))
    }
}
