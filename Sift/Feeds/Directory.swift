import Foundation

/// The directory in Follow (owner, 2026-11-17: "a dynamic directory … to
/// feed our algo"; "graph walks" only; "think smallweb first, bloggers").
/// Who the people you follow vouch for, small web first:
/// - blogrolls and OPML lists on the sites you follow,
/// - OPML follow lists you watch by address (FeedLand screen names or any
///   OPML address, `state.watchedLists`): "In <owner>'s list",
/// - Substack recommendations from the newsletters you follow,
/// - Bluesky's suggested follows for the Bluesky accounts you follow, kept
///   only when the handle is a domain (a person with their own site),
/// - Mastodon featured profiles (endorsements) of the accounts you follow,
/// - Kagi's Small Web list (github.com/kagisearch/smallweb, about 44,000
///   personal blogs), downloaded whole and matched on this Mac against the
///   sites you saved from or your feeds link to.
/// Only public ids of things you already follow leave the Mac (a site's
/// address, a publication id, a handle). No theme words, no titles.
/// Finite: at most `perGroup` entries per group, built once a week.

struct DirectoryEntry: Codable, Hashable, Sendable, Identifiable {
    /// The host for blogs and newsletters; "mastodon:@user@host".
    var id: String
    var name: String
    /// What Follow takes.
    var input: String
    /// blog, newsletter or mastodon.
    var group: String
    /// Who vouches: "jvns.ca's blogroll", "Recommended by Slow Boring".
    var via: [String]
    var description: String
    var smallWeb: Bool
    var theme: String? = nil
    var themeSimilarity: Double? = nil
    var score: Double = 0
    var feedURL: String? = nil
    var lastPost: Date? = nil

    var reason: String {
        var parts: [String] = []
        let v = via.prefix(2).joined(separator: ", ") + (via.count > 2 ? " and \(via.count - 2) more" : "")
        if !v.isEmpty { parts.append(v) }
        if smallWeb { parts.append("Small web") }
        if let t = theme { parts.append("Fits \(t)") }
        return parts.joined(separator: " · ")
    }
}

enum Directory {
    static let perGroup = 12
    static let rebuildDays: Double = 7
    /// A feed needs a post this recent to be listed.
    static let freshDays: Double = 30
    static let groups: [(id: String, title: String)] = [("blog", "Blogs"), ("newsletter", "Newsletters"), ("bluesky", "Bluesky"),
                                                         ("mastodon", "Mastodon"), ("podcast", "Podcasts")]
    /// Who follows what: a Bluesky account shows when this many of the
    /// Bluesky accounts you follow follow it.
    static let coFollowMin = 2
    /// Bluesky accounts whose follows Sift reads per build.
    static let coFollowVouchers = 30

    static var fileURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "directory.json") }
    static var smallWebURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "smallweb.txt") }

    struct File: Codable {
        var built: Date?
        var entries: [DirectoryEntry] = []
        /// Ids the user said no to.
        var dismissed: [String] = []
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

    // MARK: Inputs (plain values, made on the main actor)

    struct Voucher: Sendable {
        var name: String
        /// 0…1 from what you did with this feed.
        var weight: Double
        var site: String?
        var feedURL: String
        var bluesky: String?
        var mastodon: (user: String, host: String)?
    }

    struct Inputs: Sendable {
        var vouchers: [Voucher]
        /// Hosts you follow or dismissed: never listed.
        var skip: Set<String>
        /// Hosts you saved from, with how many saves.
        var savedHosts: [String: Int]
        /// Hosts your followed feeds link to in recent items, with the feeds.
        var linkedHosts: [String: Set<String>]
        /// Theme names to search with, only when the user turned on theme
        /// searches (`state.directoryThemeSearch`); empty otherwise.
        var themeQueries: [String] = []
        /// OPML follow lists the person watches (`state.watchedLists`).
        var watchedLists: [String] = []
    }

    static func host(_ s: String) -> String? {
        let t = s.contains("://") ? s : "https://" + s
        guard let h = URL(string: t)?.host()?.lowercased() else { return nil }
        return h.replacingOccurrences(of: #"^(www\.|m\.)"#, with: "", options: .regularExpression)
    }

    // MARK: Fetching

    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func get(_ url: URL) async -> Data? {
        guard !Demo.isOn, let host = url.host() else { return nil }
        guard await HostGate.shared.admit(host) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return data.prefix(2_000_000)
    }

    static func json(_ url: String) async -> Any? {
        guard let u = URL(string: url), let d = await get(u) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    /// Kagi's Small Web hosts, downloaded at most once a month.
    static func smallWebHosts() async -> Set<String> {
        let fm = FileManager.default
        let fresh = (try? smallWebURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            .map { Date().timeIntervalSince($0) < 30 * 86_400 } ?? false
        if !fresh, let u = URL(string: "https://raw.githubusercontent.com/kagisearch/smallweb/main/smallweb.txt"),
           let d = await get(u), d.count > 10_000 {
            try? d.write(to: smallWebURL, options: .atomic)
        }
        guard fm.fileExists(atPath: smallWebURL.path(percentEncoded: false)),
              let text = try? String(contentsOf: smallWebURL, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").compactMap { host(String($0)) })
    }

    // MARK: Walks

    private static let platform = ["youtube.com", "bsky.app", "x.com", "twitter.com", "instagram.com", "tiktok.com", "threads.net",
                                   "github.com", "linkedin.com", "medium.com", "facebook.com", "reddit.com", "substack.com",
                                   "patreon.com", "wikipedia.org", "google.com", "apple.com", "amazon.com", "mastodon.social"]

    static func isPlatform(_ h: String) -> Bool {
        (platform.contains { h == $0 || h.hasSuffix("." + $0) } && !h.hasSuffix(".substack.com")) || NextDoor.noise.contains(h)
    }

    /// A site's blogroll: a `rel="blogroll"` OPML, else a page or OPML the
    /// home page links to as "blogroll". Each other site it links to counts.
    static func blogroll(site: String) async -> [(host: String, name: String)] {
        guard let base = URL(string: site), let home = await get(base) else { return [] }
        let html = String(decoding: home, as: UTF8.self)
        let own = host(site) ?? ""
        var target: URL?
        if let r = html.range(of: #"<link[^>]+rel=["']blogroll["'][^>]*>"#, options: [.regularExpression, .caseInsensitive]),
           let h = String(html[r]).range(of: #"href=["']([^"']+)["']"#, options: .regularExpression) {
            target = URL(string: String(String(String(html[r])[h]).dropFirst(6).dropLast()), relativeTo: base)
        }
        if target == nil {
            let re = try! NSRegularExpression(pattern: #"<a\b[^>]*href=["']([^"']+)["'][^>]*>(.{0,80}?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let ns = html as NSString
            for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let href = ns.substring(with: m.range(at: 1)), text = ns.substring(with: m.range(at: 2)).lowercased()
                if href.lowercased().contains("blogroll") || text.contains("blogroll") || href.lowercased().hasSuffix(".opml") {
                    target = URL(string: href, relativeTo: base); break
                }
            }
        }
        guard let target, host(target.absoluteString) == own || target.pathExtension == "opml",
              let page = await get(target) else { return [] }
        let text = String(decoding: page, as: UTF8.self)
        var out: [String: String] = [:]
        if text.contains("<opml") {
            let doc = FeedParser.opmlDocument(page)
            for o in doc.feeds.map({ ($0.site ?? $0.url, $0.title) }) + doc.sites.map({ ($0.url, $0.title) }) {
                guard let h = host(o.0), h != own, !isPlatform(h) else { continue }
                out[h] = o.1.isEmpty ? h : o.1
            }
        } else {
            let re = try! NSRegularExpression(pattern: #"<a\b[^>]*href=["'](https?://[^"']+)["'][^>]*>(.{0,120}?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let href = ns.substring(with: m.range(at: 1))
                guard let u = URL(string: href), let h = host(href), h != own, !isPlatform(h),
                      u.pathComponents.filter({ $0 != "/" }).count <= 1 else { continue }
                let name = PreviewFetcher.plain(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
                out[h] = name.isEmpty ? h : String(name.prefix(60))
            }
        }
        // A page that links to hundreds of sites is a directory, not a roll.
        return out.count > 300 ? [] : out.map { ($0.key, $0.value) }
    }

    /// A watched OPML follow list (issue #45): what the person typed, as an
    /// address. A bare name is a FeedLand screen name.
    static func listAddress(_ typed: String) -> String? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("."), !t.contains("/"), let q = t.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            return "https://feedland.com/opml?screenname=" + q
        }
        let full = t.contains("://") ? t : "https://" + t
        guard let u = URL(string: full), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host() != nil else { return nil }
        return u.absoluteString
    }

    /// Who owns a list: the FeedLand screen name, else the OPML head title,
    /// else the host.
    static func listOwner(_ address: String, title: String?) -> String {
        if let c = URLComponents(string: address), let n = c.queryItems?.first(where: { $0.name.lowercased() == "screenname" })?.value, !n.isEmpty {
            return n
        }
        if let t = title, !t.isEmpty { return t }
        return host(address) ?? address
    }

    /// The feeds in one watched list. Only the list's address leaves the Mac.
    static func watchedList(_ address: String) async -> (owner: String, feeds: [(host: String, name: String, feed: String)]) {
        guard let u = URL(string: address), let d = await get(u) else { return (listOwner(address, title: nil), []) }
        let doc = FeedParser.opmlDocument(d)
        var out: [String: (host: String, name: String, feed: String)] = [:]
        for f in doc.feeds {
            guard let h = host(f.site ?? f.url), !isPlatform(h), out[h] == nil else { continue }
            out[h] = (h, f.title.isEmpty ? h : f.title, f.url)
        }
        return (listOwner(address, title: doc.title), Array(out.values))
    }

    /// Substack's recommendations from one publication.
    static func substack(site: String) async -> [(host: String, name: String, about: String)] {
        guard let posts = await json(site + "/api/v1/archive?sort=new&limit=1") as? [[String: Any]],
              let pub = posts.first?["publication_id"] as? Int,
              let recs = await json("https://substack.com/api/v1/recommendations/from/\(pub)") as? [[String: Any]] else { return [] }
        return recs.compactMap { r in
            guard let p = r["recommendedPublication"] as? [String: Any], let name = p["name"] as? String else { return nil }
            let custom = (p["custom_domain_optional"] as? Bool == false) ? p["custom_domain"] as? String : nil
            guard let h = custom ?? (p["subdomain"] as? String).map({ $0 + ".substack.com" }) else { return nil }
            return (host(h) ?? h, name, (r["description"] as? String) ?? (p["hero_text"] as? String) ?? "")
        }
    }

    /// Bluesky's suggested follows for an account, only people whose handle
    /// is their own domain.
    static func bluesky(actor: String) async -> [(host: String, name: String, about: String)] {
        guard let obj = await json("https://public.api.bsky.app/xrpc/app.bsky.graph.getSuggestedFollowsByActor?actor=\(actor)") as? [String: Any],
              let list = obj["suggestions"] as? [[String: Any]] else { return [] }
        return list.compactMap { s in
            guard let handle = s["handle"] as? String, !handle.hasSuffix(".bsky.social"), handle.contains("."), !isPlatform(handle) else { return nil }
            return (handle, (s["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? handle, (s["description"] as? String) ?? "")
        }
    }

    /// Who an account follows on Bluesky (public, first 100).
    static func blueskyFollows(actor: String) async -> [(handle: String, name: String, about: String)] {
        guard let obj = await json("https://public.api.bsky.app/xrpc/app.bsky.graph.getFollows?actor=\(actor)&limit=100") as? [String: Any],
              let list = obj["follows"] as? [[String: Any]] else { return [] }
        return list.compactMap { s in
            guard let handle = s["handle"] as? String else { return nil }
            return (handle, (s["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? handle, (s["description"] as? String) ?? "")
        }
    }

    private static func query(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }

    /// Theme search: members of the two best Bluesky starter packs.
    static func starterPacks(_ q: String) async -> [(handle: String, name: String, about: String, pack: String)] {
        guard let obj = await json("https://public.api.bsky.app/xrpc/app.bsky.graph.searchStarterPacks?q=\(query(q))&limit=2") as? [String: Any],
              let packs = obj["starterPacks"] as? [[String: Any]] else { return [] }
        var out: [(String, String, String, String)] = []
        for p in packs {
            guard let uri = p["uri"] as? String,
                  let sp = (await json("https://public.api.bsky.app/xrpc/app.bsky.graph.getStarterPack?starterPack=\(query(uri))") as? [String: Any])?["starterPack"] as? [String: Any],
                  let list = (sp["list"] as? [String: Any])?["uri"] as? String,
                  let items = (await json("https://public.api.bsky.app/xrpc/app.bsky.graph.getList?list=\(query(list))&limit=50") as? [String: Any])?["items"] as? [[String: Any]] else { continue }
            let name = ((sp["record"] as? [String: Any])?["name"] as? String) ?? "a starter pack"
            for i in items {
                guard let s = i["subject"] as? [String: Any], let h = s["handle"] as? String else { continue }
                out.append((h, (s["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? h, (s["description"] as? String) ?? "", name))
            }
        }
        return out
    }

    /// Theme search: Apple Podcasts (the feed address comes with each result).
    static func podcasts(_ q: String) async -> [(feed: String, name: String, about: String)] {
        guard let obj = await json("https://itunes.apple.com/search?media=podcast&limit=10&term=\(query(q))") as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let feed = r["feedUrl"] as? String, let name = r["collectionName"] as? String else { return nil }
            return (feed, name, (r["primaryGenreName"] as? String) ?? "")
        }
    }

    /// Theme search: sites that well-liked Hacker News stories come from, 2+ times.
    static func hackerNews(_ q: String) async -> [String] {
        guard let obj = await json("https://hn.algolia.com/api/v1/search?query=\(query(q))&tags=story&numericFilters=points%3E100&hitsPerPage=50") as? [String: Any],
              let hits = obj["hits"] as? [[String: Any]] else { return [] }
        var counts: [String: Int] = [:]
        for h in hits { if let u = h["url"] as? String, let host = host(u), !isPlatform(host) { counts[host, default: 0] += 1 } }
        return counts.filter { $0.value >= 2 }.map(\.key)
    }

    /// Theme search: ooh.directory, a hand-kept directory of blogs.
    static func oohDirectory(_ q: String) async -> [(host: String, name: String)] {
        guard let u = URL(string: "https://ooh.directory/search/?q=\(query(q))"), let d = await get(u) else { return [] }
        let html = String(decoding: d, as: UTF8.self)
        let re = try! NSRegularExpression(pattern: #"<a[^>]+href="(https?://[^"]+)"[^>]*>([^<]{2,80})</a>"#)
        let ns = html as NSString
        var out: [String: String] = [:]
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = ns.substring(with: m.range(at: 1))
            guard let h = host(href), h != "ooh.directory", !isPlatform(h), let url = URL(string: href),
                  url.pathComponents.filter({ $0 != "/" }).count <= 1, out[h] == nil else { continue }
            out[h] = PreviewFetcher.plain(ns.substring(with: m.range(at: 2)))
        }
        return out.map { ($0.key, $0.value) }
    }

    /// Mastodon featured profiles of one account.
    static func mastodon(user: String, host: String) async -> [(input: String, name: String, about: String)] {
        guard let acct = await json("https://\(host)/api/v1/accounts/lookup?acct=\(user)") as? [String: Any],
              let id = acct["id"] as? String,
              let list = await json("https://\(host)/api/v1/accounts/\(id)/endorsements") as? [[String: Any]] else { return [] }
        return list.compactMap { a in
            guard let acct = a["acct"] as? String else { return nil }
            let full = acct.contains("@") ? acct : acct + "@" + host
            let about = PreviewFetcher.plain(((a["note"] as? String) ?? "").replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
            return ("@" + full, (a["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "@" + full, about)
        }
    }

    // MARK: Building

    /// Walks out from every voucher, merges by site, adds Small Web matches,
    /// then checks the best entries for a fresh feed.
    static func build(_ input: Inputs, space: Meaning.Space) async -> [DirectoryEntry] {
        var acc: [String: DirectoryEntry] = [:]
        var weights: [String: [Double]] = [:]
        func add(id: String, name: String, input inp: String, group: String, via: String, about: String, weight: Double) {
            guard !input.skip.contains(id) else { return }
            if acc[id] == nil { acc[id] = DirectoryEntry(id: id, name: name, input: inp, group: group, via: [], description: about, smallWeb: false) }
            if !acc[id]!.via.contains(via) { acc[id]!.via.append(via); weights[id, default: []].append(weight) }
            if acc[id]!.description.isEmpty { acc[id]!.description = about }
        }
        for v in input.vouchers {
            if let site = v.site {
                for b in await blogroll(site: site) {
                    add(id: b.host, name: b.name, input: b.host, group: b.host.hasSuffix(".substack.com") ? "newsletter" : "blog",
                        via: "In \(v.name)'s blogroll", about: "", weight: v.weight)
                }
                if v.feedURL.hasSuffix("/feed") {
                    for s in await substack(site: site) {
                        add(id: s.host, name: s.name, input: s.host, group: "newsletter", via: "Recommended by \(v.name)", about: s.about, weight: v.weight)
                    }
                }
            }
            if let actor = v.bluesky {
                for b in await bluesky(actor: actor) {
                    add(id: b.host, name: b.name, input: b.host, group: "blog", via: "Suggested on Bluesky for \(v.name)", about: b.about, weight: v.weight)
                }
            }
            if let m = v.mastodon {
                for a in await mastodon(user: m.user, host: m.host) {
                    add(id: "mastodon:" + a.input.lowercased(), name: a.name, input: a.input, group: "mastodon",
                        via: "Featured by \(v.name)", about: a.about, weight: v.weight)
                }
            }
        }
        // Who follows what: the feeds in the OPML lists you watch.
        for address in input.watchedLists {
            let list = await watchedList(address)
            for f in list.feeds {
                add(id: f.host, name: f.name, input: f.feed, group: f.host.hasSuffix(".substack.com") ? "newsletter" : "blog",
                    via: "In \(list.owner)'s list", about: "", weight: 0.5)
            }
        }
        // Who follows what: the Bluesky accounts your Bluesky follows follow.
        for v in input.vouchers.filter({ $0.bluesky != nil }).prefix(coFollowVouchers) {
            for f in await blueskyFollows(actor: v.bluesky!) {
                add(id: "bluesky:@" + f.handle.lowercased(), name: f.name, input: "@" + f.handle, group: "bluesky",
                    via: "Followed by \(v.name)", about: f.about, weight: v.weight)
            }
        }
        // Theme searches (opt-in): starter packs, podcasts, Hacker News, ooh.directory.
        for q in input.themeQueries {
            for m in await starterPacks(q) {
                add(id: "bluesky:@" + m.handle.lowercased(), name: m.name, input: "@" + m.handle, group: "bluesky",
                    via: "In the starter pack \(m.pack)", about: m.about, weight: 0.3)
            }
            for p in await podcasts(q) {
                add(id: "podcast:" + p.feed.lowercased(), name: p.name, input: p.feed, group: "podcast",
                    via: "Apple Podcasts for \(q)", about: p.about, weight: 0.3)
            }
            for h in await hackerNews(q) {
                add(id: h, name: h, input: h, group: "blog", via: "Liked on Hacker News for \(q)", about: "", weight: 0.3)
            }
            for b in await oohDirectory(q) {
                add(id: b.host, name: b.name, input: b.host, group: "blog", via: "ooh.directory for \(q)", about: "", weight: 0.3)
            }
        }
        // Small web: the personal sites you already save from or your feeds link to.
        let small = await smallWebHosts()
        for (h, n) in input.savedHosts where small.contains(h) {
            add(id: h, name: h, input: h, group: "blog", via: "You saved \(n) from it", about: "", weight: 0.5)
        }
        for (h, feeds) in input.linkedHosts where small.contains(h) {
            add(id: h, name: h, input: h, group: "blog", via: "Linked from \(feeds.sorted().prefix(2).joined(separator: ", "))", about: "", weight: 0.5)
        }
        // Score: each voucher adds 1 + its weight; the small web counts 1.3×;
        // meaning lifts it up to 2× toward a theme you have.
        var list: [DirectoryEntry] = []
        let embedder = space.isEmpty ? nil : Embedder()
        for (id, var e) in acc {
            // A Bluesky account from follows alone needs 2+ of yours following it.
            let follows = e.via.filter { $0.hasPrefix("Followed by ") }.count
            if e.group == "bluesky", follows > 0, follows < coFollowMin, !e.via.contains(where: { !$0.hasPrefix("Followed by ") }) { continue }
            e.smallWeb = small.contains(id)
            var s = 0.0
            for w in weights[id] ?? [] { s += 1 + w }
            if e.smallWeb { s *= 1.3 }
            if let embedder, !e.description.isEmpty, let raw = embedder.vector(Meaning.text(title: e.name, preview: e.description)),
               let v = space.place(raw), let t = space.theme(for: v) {
                e.theme = t.name
                e.themeSimilarity = t.cos
                s *= 1 + max(0, t.cos)
            }
            e.score = (s * 100).rounded() / 100
            list.append(e)
        }
        // Per group, best first: keep those with a feed that posted lately.
        var out: [DirectoryEntry] = []
        for g in groups {
            var kept = 0
            for var e in list.filter({ $0.group == g.id }).sorted(by: { $0.score > $1.score }).prefix(perGroup * 3) where kept < perGroup {
                guard let found = await FeedProviders.resolve(e.input).first else { continue }
                let last = found.parsed.entries.compactMap(\.date).max()
                guard let last, Date().timeIntervalSince(last) < freshDays * 86_400 else { continue }
                if e.name == e.id, !found.parsed.title.isEmpty { e.name = found.parsed.title }
                e.feedURL = found.url
                e.lastPost = last
                out.append(e)
                kept += 1
            }
        }
        return out
    }
}
