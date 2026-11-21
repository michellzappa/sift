import Foundation

/// People (owner, 2026-11-17: "a SOLID follow model where we follow across
/// platforms into our various feeds … let creators own their feeds"). One
/// person, many places: a site, a YouTube channel, a Bluesky account, a
/// newsletter, a podcast. Sift finds them from what the person publishes
/// about themselves, never from a Sift directory:
/// - `rel="me"` links on their site (the IndieWeb way to say "this is also
///   me"; Mastodon verifies profiles the same way),
/// - the one profile per platform their home page links to (a blog that
///   links to many YouTube channels says nothing, and is skipped),
/// - a Bluesky handle that is a domain (bsky.app proves the person controls
///   it) and the links in their Bluesky bio.
/// Follow a person and Sift follows each place that has a feed. Platforms
/// without feeds (X, Instagram, TikTok, LinkedIn, Threads) show as links.
/// Local: the pages are fetched like any feed, paced by HostGate.

/// One place where a person publishes.
struct Place: Codable, Hashable, Sendable, Identifiable {
    /// site, youtube, bluesky, mastodon, substack, medium, github, podcast,
    /// x, instagram, tiktok, threads, linkedin.
    var platform: String
    /// The profile page.
    var url: String
    /// "@simonw.bsky.social", "simonwillison.net", "@veritasium".
    var handle: String
    var id: String { platform + ":" + handle.lowercased() }

    /// What Follow takes, for platforms that have feeds.
    var followInput: String? {
        switch platform {
        case "site", "substack": handle
        case "youtube": url
        case "bluesky": handle
        case "mastodon": handle
        case "medium": "medium.com/" + handle
        case "github": "https://github.com/" + handle.dropFirst() + ".atom"
        case "podcast": url
        default: nil
        }
    }
    var hasFeed: Bool { followInput != nil }

    static let names: [String: String] = [
        "site": "Website", "youtube": "YouTube", "bluesky": "Bluesky", "mastodon": "Mastodon", "substack": "Substack",
        "medium": "Medium", "github": "GitHub", "podcast": "Podcast", "x": "X", "instagram": "Instagram",
        "tiktok": "TikTok", "threads": "Threads", "linkedin": "LinkedIn",
    ]
    var platformName: String { Self.names[platform] ?? platform }
    var symbol: String {
        switch platform {
        case "youtube": "play.rectangle"
        case "podcast": "mic"
        case "github": "chevron.left.forwardslash.chevron.right"
        case "bluesky", "mastodon", "x", "threads": "bubble.left"
        case "instagram", "tiktok": "camera"
        case "substack", "medium": "envelope"
        case "linkedin": "person.crop.square"
        default: "globe"
        }
    }
}

/// A person and every place Sift found for them.
struct Person: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var profiles: [Place]
    /// How Sift knows: "simonwillison.net links to it with rel=me".
    var evidence: [String]
    var found: Date
}

enum People {
    static var fileURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "people.json") }
    /// Seeds checked per round, and how long a check holds.
    static let perRound = 40
    static let recheckDays: Double = 14

    struct File: Codable {
        var people: [Person] = []
        /// Seed profile id → when it was checked, with what it found.
        var checked: [String: Seed] = [:]
        /// People the user said are not one person.
        var hidden: [String] = []
    }

    struct Seed: Codable, Hashable, Sendable {
        var at: Date
        var name: String
        var found: [Place]
        var evidence: [String]
        /// The same place under its better name: a YouTube channel seed
        /// (by channel id) and its @handle. `merge` shows the alias and
        /// treats both ids as one place.
        var alias: Place?
    }

    static func load() -> File {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL) else { return File() }
        return (try? d.decode(File.self, from: data)) ?? File()
    }

    static func save(_ f: File) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? e.encode(f) { try? data.write(to: fileURL, options: .atomic) }
    }

    // MARK: Profiles from links

    private static let platformHosts: Set<String> = [
        "youtube.com", "bsky.app", "x.com", "twitter.com", "instagram.com", "tiktok.com", "threads.net", "threads.com",
        "github.com", "linkedin.com", "medium.com", "podcasts.apple.com", "facebook.com", "reddit.com",
    ]
    private static let reservedPaths: Set<String> = [
        "intent", "share", "home", "search", "i", "explore", "p", "reel", "reels", "watch", "playlist", "results", "hashtag",
        "sponsors", "orgs", "about", "login", "signup", "settings", "features", "topics", "embed", "status", "tags", "tag",
    ]

    static func host(_ link: String) -> String? {
        guard let h = URL(string: link)?.host()?.lowercased() else { return nil }
        return h.replacingOccurrences(of: #"^(www\.|m\.|mobile\.)"#, with: "", options: .regularExpression)
    }

    /// The profile a link names, if it is a profile page. `relMe` allows a
    /// plain site and Mastodon-like /@user pages on any host.
    static func profile(_ link: String, relMe: Bool) -> Place? {
        guard let u = URL(string: link), ["http", "https"].contains(u.scheme ?? ""), let host = host(link) else { return nil }
        let parts = u.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let first = parts.first ?? ""
        func ok(_ s: String) -> Bool { !s.isEmpty && !reservedPaths.contains(s.lowercased()) && s.count <= 40 }
        switch host {
        case "youtube.com":
            if first.hasPrefix("@"), parts.count <= 2 { return Place(platform: "youtube", url: "https://www.youtube.com/\(first)", handle: first) }
            if ["channel", "c", "user"].contains(first), parts.count >= 2 {
                return Place(platform: "youtube", url: "https://www.youtube.com/\(first)/\(parts[1])", handle: parts[1])
            }
            return nil
        case "bsky.app":
            guard first == "profile", parts.count == 2 else { return nil }
            return Place(platform: "bluesky", url: link, handle: "@" + parts[1].lowercased())
        case "x.com", "twitter.com":
            guard parts.count == 1, ok(first) else { return nil }
            return Place(platform: "x", url: "https://x.com/\(first)", handle: "@" + first)
        case "instagram.com":
            guard parts.count == 1, ok(first) else { return nil }
            return Place(platform: "instagram", url: "https://www.instagram.com/\(first)/", handle: "@" + first)
        case "tiktok.com":
            guard parts.count == 1, first.hasPrefix("@") else { return nil }
            return Place(platform: "tiktok", url: "https://www.tiktok.com/\(first)", handle: first)
        case "threads.net", "threads.com":
            guard parts.count == 1, first.hasPrefix("@") else { return nil }
            return Place(platform: "threads", url: "https://www.threads.com/\(first)", handle: first)
        case "github.com":
            guard parts.count == 1, ok(first) else { return nil }
            return Place(platform: "github", url: "https://github.com/\(first)", handle: "@" + first)
        case "linkedin.com":
            guard parts.count == 2, first == "in" else { return nil }
            return Place(platform: "linkedin", url: "https://www.linkedin.com/in/\(parts[1])", handle: parts[1])
        case "medium.com":
            guard parts.count == 1, first.hasPrefix("@") else { return nil }
            return Place(platform: "medium", url: "https://medium.com/\(first)", handle: first)
        case "podcasts.apple.com":
            guard link.range(of: #"/id\d+"#, options: .regularExpression) != nil else { return nil }
            return Place(platform: "podcast", url: link.components(separatedBy: "?").first ?? link, handle: parts.dropLast().last ?? "podcast")
        default:
            if host.hasSuffix(".substack.com"), parts.isEmpty { return Place(platform: "substack", url: "https://\(host)", handle: host) }
            if platformHosts.contains(where: { host.hasSuffix($0) }) { return nil }
            guard relMe else { return nil }
            if parts.count == 1, first.hasPrefix("@"), first.count > 1 {
                return Place(platform: "mastodon", url: "https://\(host)/\(first)", handle: first + "@" + host)
            }
            if parts.isEmpty { return Place(platform: "site", url: "https://\(host)", handle: host) }
            return nil
        }
    }

    // MARK: Reading pages

    private static let anchor = try! NSRegularExpression(pattern: #"<(?:a|link)\b[^>]*>"#, options: .caseInsensitive)
    private static let href = try! NSRegularExpression(pattern: #"\bhref\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive)
    private static let relMeAttr = try! NSRegularExpression(pattern: #"\brel\s*=\s*["'][^"']*\bme\b[^"']*["']"#, options: .caseInsensitive)

    /// Profiles a home page claims: every rel=me link, and each platform the
    /// page links to exactly one profile of whose handle matches the site
    /// (its domain or name). A lone link in a post or a sponsor note (a
    /// LinkedIn profile on Daring Fireball, 2026-11-17 test) does not count.
    static func claims(html: String, base: URL, owner: [String] = []) -> (profiles: [Place], relMe: Set<String>) {
        let ns = html as NSString
        var rel: [Place] = []
        var plain: [String: Set<Place>] = [:]
        for m in anchor.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            let t = tag as NSString
            guard let h = href.firstMatch(in: tag, range: NSRange(location: 0, length: t.length)) else { continue }
            let raw = t.substring(with: h.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard let abs = URL(string: raw, relativeTo: base)?.absoluteString else { continue }
            let isMe = relMeAttr.firstMatch(in: tag, range: NSRange(location: 0, length: t.length)) != nil
            if isMe, let p = profile(abs, relMe: true) { rel.append(p); continue }
            if let p = profile(abs, relMe: false) { plain[p.platform, default: []].insert(p) }
        }
        var out = rel
        let relPlatforms = Set(rel.map(\.platform))
        for (platform, set) in plain where set.count == 1 && !relPlatforms.contains(platform) {
            if resembles(set.first!.handle, owner) { out.append(set.first!) }
        }
        var seen = Set<String>()
        out = out.filter { seen.insert($0.id).inserted }
        return (out, Set(rel.map(\.id)))
    }

    /// True when a handle and one of the owner's names share a run of 4+
    /// letters or digits ("michellzappa" and michellzappa.com, "@gruber" and
    /// "John Gruber").
    static func resembles(_ handle: String, _ owner: [String]) -> Bool {
        let h = handle.lowercased().filter { $0.isLetter || $0.isNumber }
        guard h.count >= 3 else { return false }
        for o in owner {
            for word in o.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where word.count >= 4 {
                if h.contains(word) { return true }
            }
            let flat = o.lowercased().filter { $0.isLetter || $0.isNumber }
            if flat.count >= 4, flat.contains(h) || h.contains(flat) { return true }
        }
        return false
    }

    static func siteName(html: String) -> String? {
        for pattern in [#"<meta[^>]+property=["']og:site_name["'][^>]+content=["']([^"']+)["']"#,
                        #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:site_name["']"#,
                        #"<title[^>]*>([^<]{2,80})</title>"#] {
            if let r = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
               let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let m = re.firstMatch(in: String(html[r]), range: NSRange(location: 0, length: (String(html[r]) as NSString).length)) {
                let v = (String(html[r]) as NSString).substring(with: m.range(at: 1))
                let clean = PreviewFetcher.plain(v).components(separatedBy: CharacterSet(charactersIn: "|–—")).first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if !clean.isEmpty { return clean }
            }
        }
        return nil
    }

    /// `gate` and `cookie` for YouTube: gate "youtube.com" and the standard
    /// consent cookie (no account), as `YouTubeProvider` does.
    private static func get(_ url: URL, gate: String? = nil, cookie: String? = nil, limit: Int = 1_500_000) async -> String? {
        guard !Demo.isOn, let host = url.host() else { return nil }
        guard await HostGate.shared.admit(gate ?? host) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if let cookie {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
            req.httpShouldHandleCookies = false
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 429 || http.statusCode == 503 { await HostGate.shared.pause(gate ?? host, seconds: 3600) }
        guard (200..<300).contains(http.statusCode) else { return nil }
        return String(decoding: data.prefix(limit), as: UTF8.self)
    }

    /// A YouTube channel's About data without a login (checked live
    /// 2026-11-21): `/channel/<id>/about` with the consent cookie carries
    /// `channelMetadataRenderer` (title, vanityChannelUrl) and one
    /// `channelExternalLinkViewModel` per link the channel lists, near the
    /// end of a 3 MB page. The plain channel page has no links. Each link's
    /// redirect carries the full address in `q=`; the shown text is the
    /// fallback (it has no scheme).
    struct ChannelAbout {
        var title: String?
        var handle: String?
        var links: [(title: String, url: String)]
    }

    private static let externalLink = try! NSRegularExpression(
        pattern: #""channelExternalLinkViewModel":\{"title":\{"content":"((?:[^"\\]|\\.)*)"\},"link":\{"content":"((?:[^"\\]|\\.)*)""#)

    static func channelAbout(html: String) -> ChannelAbout {
        let ns = html as NSString
        func first(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return ns.substring(with: m.range(at: 1))
        }
        func unescape(_ s: String) -> String {
            (try? JSONSerialization.jsonObject(with: Data("\"\(s)\"".utf8), options: .fragmentsAllowed) as? String) ?? s
        }
        var about = ChannelAbout(title: first(#""channelMetadataRenderer":\{"title":"((?:[^"\\]|\\.)*)""#).map(unescape),
                                 handle: first(#""vanityChannelUrl":"https?://www\.youtube\.com/(@[^"/?]+)""#), links: [])
        let matches = externalLink.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for (i, m) in matches.enumerated() {
            let title = unescape(ns.substring(with: m.range(at: 1)))
            var link = unescape(ns.substring(with: m.range(at: 2)))
            // The redirect's q= before the next link holds the full address.
            let end = i + 1 < matches.count ? matches[i + 1].range.location : min(ns.length, m.range.upperBound + 4000)
            let rest = ns.substring(with: NSRange(location: m.range.upperBound, length: max(0, end - m.range.upperBound)))
            if let r = rest.range(of: #"(?:\\u0026|&|\?)q=([^"\\&]+)"#, options: .regularExpression),
               let q = String(rest[r]).components(separatedBy: "q=").last?.removingPercentEncoding, q.hasPrefix("http") {
                link = q
            } else if !link.hasPrefix("http") {
                link = "https://" + link
            }
            about.links.append((title, link))
        }
        return about
    }

    /// What one seed says about its person: a site's home page, or a Bluesky
    /// profile through the public AppView (no login).
    static func check(_ seed: Place, name: String) async -> Seed {
        var found: [Place] = []
        var evidence: [String] = []
        var name = name
        var alias: Place? = nil
        switch seed.platform {
        case "site", "substack":
            guard let url = URL(string: seed.url), let html = await get(url) else { break }
            let label = seed.handle.components(separatedBy: ".").dropLast().joined(separator: " ")
            let (profiles, relMe) = claims(html: html, base: url, owner: [label, name, siteName(html: html) ?? ""])
            for p in profiles where p.id != seed.id {
                found.append(p)
                evidence.append(relMe.contains(p.id)
                                ? "\(seed.handle) links to \(p.platformName) \(p.handle) with rel=me"
                                : "\(seed.handle) links to \(p.platformName) \(p.handle)")
            }
            if let n = siteName(html: html), name.isEmpty || name == seed.handle { name = n }
        case "bluesky":
            let actor = String(seed.handle.dropFirst())
            guard let url = URL(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=\(actor)"),
                  let text = await get(url), let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { break }
            if let d = obj["displayName"] as? String, !d.isEmpty { name = d }
            // A domain handle is proof: bsky.app checked the person controls it.
            if let handle = obj["handle"] as? String, !handle.hasSuffix(".bsky.social"), handle.contains(".") {
                found.append(Place(platform: "site", url: "https://\(handle)", handle: handle))
                evidence.append("Bluesky \(seed.handle) uses the domain \(handle) as its handle")
            }
            let bio = obj["description"] as? String ?? ""
            var perPlatform: [String: Set<Place>] = [:]
            for m in NextDoor.linkPattern.matches(in: bio, range: NSRange(location: 0, length: (bio as NSString).length)) {
                let link = (bio as NSString).substring(with: m.range)
                if let p = profile(link, relMe: true), p.id != seed.id { perPlatform[p.platform, default: []].insert(p) }
            }
            for (_, set) in perPlatform where set.count == 1 {
                found.append(set.first!)
                evidence.append("the Bluesky bio of \(seed.handle) links to \(set.first!.handle)")
            }
        case "youtube":
            // A channel seed (by channel id): the links the channel lists on
            // its About page are its own claims, like rel=me. One profile
            // per platform; a site only when it resembles the channel.
            guard seed.handle.hasPrefix("UC"), let url = URL(string: "https://www.youtube.com/channel/\(seed.handle)/about"),
                  let html = await get(url, gate: "youtube.com", cookie: "SOCS=CAI; CONSENT=YES+cb", limit: 8_000_000) else { break }
            let about = channelAbout(html: html)
            if let t = about.title, !t.isEmpty { name = t }
            if let h = about.handle {
                alias = Place(platform: "youtube", url: "https://www.youtube.com/channel/\(seed.handle)", handle: h)
            }
            let shown = "YouTube channel " + (about.title ?? about.handle ?? seed.handle)
            let owner = [name, about.handle ?? "", about.title ?? ""]
            var perPlatform: [String: Set<Place>] = [:]
            for link in about.links {
                guard let p = profile(link.url, relMe: true), p.platform != "youtube" else { continue }
                if p.platform == "site", !resembles(p.handle.components(separatedBy: ".").dropLast().joined(), owner) { continue }
                perPlatform[p.platform, default: []].insert(p)
            }
            for (_, set) in perPlatform where set.count == 1 {
                found.append(set.first!)
                evidence.append("\(shown) links to \(set.first!.platformName) \(set.first!.handle)")
            }
        default:
            break
        }
        return Seed(at: Date(), name: name, found: found, evidence: evidence, alias: alias)
    }

    // MARK: Merging

    /// Joins seeds that share a profile into people. A person needs two
    /// places or more. The id is the site's profile id when there is one,
    /// so it stays put when Sift finds more places later.
    static func merge(_ checked: [String: Seed], seeds: [String: Place]) -> [Person] {
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            var x = x
            while let p = parent[x], p != x { parent[x] = parent[p]; x = p }
            return x
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if parent[ra] == nil { parent[ra] = ra }
            if parent[rb] == nil { parent[rb] = rb }
            if ra != rb { parent[rb] = ra }
        }
        var profiles: [String: Place] = [:]
        var names: [String: String] = [:]
        var evidence: [String: [String]] = [:]
        // A seed with an alias (a YouTube channel id and its @handle) is one
        // place under the alias id, whichever id another seed found.
        var canon: [String: String] = [:]
        for (seedID, s) in checked { if let a = s.alias { canon[seedID] = a.id } }
        for (seedID, s) in checked {
            guard let seed = seeds[seedID] else { continue }
            let me = s.alias ?? seed
            profiles[me.id] = s.alias ?? profiles[me.id] ?? seed
            if parent[me.id] == nil { parent[me.id] = me.id }
            if !s.name.isEmpty { names[me.id] = s.name }
            for p in s.found {
                let id = canon[p.id] ?? p.id
                if profiles[id] == nil { profiles[id] = p }
                union(me.id, id)
            }
            evidence[me.id, default: []].append(contentsOf: s.evidence)
        }
        var groups: [String: [String]] = [:]
        for id in profiles.keys { groups[find(id), default: []].append(id) }
        var out: [Person] = []
        for (_, ids) in groups where ids.count >= 2 {
            let list = ids.compactMap { profiles[$0] }.sorted { a, b in
                let order = ["site", "substack", "youtube", "bluesky", "mastodon", "podcast", "medium", "github", "x", "instagram", "tiktok", "threads", "linkedin"]
                return (order.firstIndex(of: a.platform) ?? 99, a.handle) < (order.firstIndex(of: b.platform) ?? 99, b.handle)
            }
            let id = list.first { $0.platform == "site" }?.id ?? list[0].id
            let name = ids.compactMap { names[$0] }.min { $0.count < $1.count } ?? list[0].handle
            out.append(Person(id: id, name: name, profiles: list, evidence: Array(Set(ids.flatMap { evidence[$0] ?? [] })).sorted(), found: Date()))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Matching feeds

    /// The profile a followed feed is, when Sift can tell.
    static func profile(of feed: Feed) -> Place? {
        if let p = feed.place, let platform = p.split(separator: ":").first, let handle = p.split(separator: ":", maxSplits: 1).last {
            return Place(platform: String(platform), url: feed.site ?? feed.url, handle: String(handle))
        }
        let url = feed.url.lowercased()
        if let r = url.range(of: #"bsky\.app/profile/([^/]+)"#, options: .regularExpression) {
            let h = String(url[r]).components(separatedBy: "/").last ?? ""
            return Place(platform: "bluesky", url: feed.url, handle: "@" + h)
        }
        if feed.provider == "youtube" || url.contains("youtube.com/feeds") { return nil }
        if let r = url.range(of: #"^https?://([^/]+)/@([^/.]+)\.rss$"#, options: .regularExpression) {
            let parts = String(url[r]).components(separatedBy: "/")
            if parts.count >= 4 { return Place(platform: "mastodon", url: feed.url, handle: parts[3].replacingOccurrences(of: ".rss", with: "") + "@" + parts[2]) }
        }
        if url.hasPrefix("https://github.com/"), url.hasSuffix(".atom"), let u = URL(string: feed.url), u.pathComponents.count == 2 {
            return Place(platform: "github", url: "https://github.com/\(u.deletingPathExtension().lastPathComponent)", handle: "@" + u.deletingPathExtension().lastPathComponent)
        }
        guard let h = host(feed.site ?? feed.url) else { return nil }
        if h.hasSuffix(".substack.com") { return Place(platform: "substack", url: "https://\(h)", handle: h) }
        if platformHosts.contains(where: { h.hasSuffix($0) }) { return nil }
        return Place(platform: "site", url: "https://\(h)", handle: h)
    }

    /// The channel id in a YouTube address or channel feed ("UC" + 22).
    static func channelID(_ s: String) -> String? {
        guard let r = s.range(of: #"(?:/channel/|channel_id=)UC[\w-]{22}"#, options: .regularExpression),
              let id = s[r].range(of: #"UC[\w-]{22}"#, options: .regularExpression) else { return nil }
        return String(s[r][id])
    }

    /// True when this feed is that profile: the same id, the same host for
    /// sites and newsletters, or a YouTube channel whose name matches.
    static func matches(_ feed: Feed, _ p: Place) -> Bool {
        if feed.place == p.id { return true }
        if let fp = profile(of: feed), fp.id == p.id { return true }
        let flat = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        switch p.platform {
        case "youtube":
            guard feed.provider == "youtube" || feed.url.contains("youtube.com/feeds") else { return false }
            if let id = channelID(p.url), feed.url.contains("channel_id=" + id) { return true }
            if let site = feed.site, site.lowercased().contains(p.handle.lowercased()) { return true }
            return !feed.url.contains("playlist_id") && flat(feed.title) == flat(p.handle)
        case "medium": return feed.url.lowercased().contains("medium.com/feed/" + p.handle.lowercased())
        default: return false
        }
    }
}
