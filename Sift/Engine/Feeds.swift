import Foundation

// Feeds as a source: RSS 2.0, RSS 1.0 (RDF), Atom and JSON Feed, imported
// from OPML or added by URL. Each feed's recent items live in
// Application Support/Sift/feeds/<feed id>.json (plain JSON). They show as
// one source, "Feeds", and go through the same library, themes, seen and
// search as every other link. No dependencies: XMLParser and JSONDecoder.

/// One followed feed, kept in state.json.
struct Feed: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// The feed's own URL (RSS, Atom or JSON Feed).
    var url: String
    var title: String
    /// The site the feed belongs to, when known.
    var site: String?
    /// The folder it had in the OPML file, if any.
    var category: String?
    var enabled = true
    var added: Date
    var lastFetched: Date?
    var lastError: String?
    var etag: String?
    var lastModified: String?
}

/// One item from a feed.
struct FeedEntry: Codable, Hashable, Sendable {
    var url: String
    var title: String
    var date: Date?
    var author: String?
    /// Plain text, at most about 1,200 characters.
    var summary: String
    var image: String?
}

enum FeedStore {
    static let sourceID = "feeds"
    /// Items kept per feed, and for how long.
    static let keepPerFeed = 150
    static let keepDays: Double = 90

    static var folder: URL {
        let dir = StateFile.url.deletingLastPathComponent().appending(path: "feeds", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ id: String) -> URL { folder.appending(path: "\(id).json") }

    static func entries(_ id: String) -> [FeedEntry] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file(id)) else { return [] }
        return (try? d.decode([FeedEntry].self, from: data)) ?? []
    }

    /// Merges new items into the stored ones, newest first, by URL.
    static func merge(_ new: [FeedEntry], into id: String) -> Int {
        var byURL = Dictionary(entries(id).map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0
        for e in new where !e.url.isEmpty {
            if byURL[e.url] == nil { added += 1 }
            byURL[e.url] = e
        }
        let cutoff = Date().addingTimeInterval(-keepDays * 86_400)
        let kept = byURL.values
            .filter { ($0.date ?? .now) >= cutoff }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(keepPerFeed)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        if let data = try? e.encode(Array(kept)) { try? data.write(to: file(id), options: .atomic) }
        return added
    }

    static func remove(_ id: String) { try? FileManager.default.removeItem(at: file(id)) }
}

// MARK: - Parsing

enum FeedParser {
    struct Parsed: Sendable {
        var title: String
        var site: String?
        var entries: [FeedEntry]
    }

    /// RSS, RDF, Atom or JSON Feed. Nil when the data is none of them.
    static func parse(_ data: Data, base: URL) -> Parsed? {
        let head = String(decoding: data.prefix(400), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("{") { return json(data, base: base) }
        let delegate = XMLFeed(base: base)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !delegate.entries.isEmpty, delegate.isFeed else { return nil }
        return Parsed(title: delegate.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                      site: delegate.feedLink, entries: delegate.entries)
    }

    private static func json(_ data: Data, base: URL) -> Parsed? {
        struct JF: Decodable {
            struct Author: Decodable { var name: String? }
            struct Item: Decodable {
                var url: String?; var external_url: String?; var title: String?
                var content_html: String?; var content_text: String?; var summary: String?
                var date_published: String?; var image: String?; var banner_image: String?
                var authors: [Author]?; var author: Author?
            }
            var version: String?; var title: String?; var home_page_url: String?; var items: [Item]?
        }
        guard let f = try? JSONDecoder().decode(JF.self, from: data), f.version?.contains("jsonfeed") == true else { return nil }
        let entries = (f.items ?? []).compactMap { i -> FeedEntry? in
            guard let link = i.url ?? i.external_url, let u = URL(string: link, relativeTo: base) else { return nil }
            let text = i.content_text ?? i.summary ?? i.content_html.map(PreviewFetcher.plain) ?? ""
            return FeedEntry(url: u.absoluteString, title: i.title ?? "", date: Dates.parse(i.date_published),
                             author: i.authors?.first?.name ?? i.author?.name, summary: Text.trim(text),
                             image: i.image ?? i.banner_image)
        }
        return Parsed(title: f.title ?? base.host() ?? "Feed", site: f.home_page_url, entries: entries)
    }

    enum Text {
        static func trim(_ s: String) -> String {
            let flat = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return flat.count > 1_200 ? String(flat.prefix(1_200)) + "…" : flat
        }
    }

    enum Dates {
        nonisolated(unsafe) private static let rfc822: [DateFormatter] = [
            "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm:ss Z",
        ].map { f in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            return df
        }

        static func parse(_ s: String?) -> Date? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            if let d = try? Date(s, strategy: .iso8601) { return d }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            for f in rfc822 { if let d = f.date(from: s) { return d } }
            return nil
        }
    }

    /// Reads OPML: every outline with an xmlUrl, with its parent folder.
    static func opml(_ data: Data) -> [(url: String, title: String, site: String?, category: String?)] {
        final class Delegate: NSObject, XMLParserDelegate {
            var feeds: [(url: String, title: String, site: String?, category: String?)] = []
            var folders: [String?] = []
            func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                guard name.lowercased() == "outline" else { return }
                let title = a["title"] ?? a["text"] ?? ""
                if let url = a["xmlUrl"] ?? a["xmlurl"], !url.isEmpty {
                    feeds.append((url, title, a["htmlUrl"] ?? a["htmlurl"], folders.compactMap { $0 }.last))
                    folders.append(nil)
                } else {
                    folders.append(title.isEmpty ? nil : title)
                }
            }
            func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                if name.lowercased() == "outline", !folders.isEmpty { folders.removeLast() }
            }
        }
        let d = Delegate()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        var seen = Set<String>()
        return d.feeds.filter { seen.insert($0.url).inserted }
    }

    /// OPML for the followed feeds, grouped by category.
    static func opml(_ feeds: [Feed]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        func line(_ f: Feed) -> String {
            "<outline type=\"rss\" text=\"\(esc(f.title))\" title=\"\(esc(f.title))\" xmlUrl=\"\(esc(f.url))\"\(f.site.map { " htmlUrl=\"\(esc($0))\"" } ?? "")/>"
        }
        var body = ""
        for (category, list) in Dictionary(grouping: feeds, by: { $0.category ?? "" }).sorted(by: { $0.key < $1.key }) {
            if category.isEmpty {
                body += list.map { "    " + line($0) }.joined(separator: "\n") + "\n"
            } else {
                body += "    <outline text=\"\(esc(category))\" title=\"\(esc(category))\">\n"
                body += list.map { "      " + line($0) }.joined(separator: "\n") + "\n    </outline>\n"
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Sift feeds</title></head>
          <body>
        \(body)  </body>
        </opml>
        """
    }
}

/// XMLParser delegate for RSS 2.0, RSS 1.0 and Atom.
private final class XMLFeed: NSObject, XMLParserDelegate {
    let base: URL
    var isFeed = false
    var feedTitle = ""
    var feedLink: String?
    var entries: [FeedEntry] = []

    private var inItem = false
    private var text = ""
    private var item: [String: String] = [:]
    private var image: String?
    private var link: String?
    private var depthTitleSet = false

    init(base: URL) { self.base = base }

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = name.lowercased()
        text = ""
        switch n {
        case "rss", "feed", "rdf:rdf", "channel": isFeed = true
        case "item", "entry":
            inItem = true; item = [:]; image = nil; link = nil
        case "link":
            // Atom: <link rel="alternate" href="…"/>
            if let href = a["href"] {
                let rel = a["rel"] ?? "alternate"
                if rel == "alternate" {
                    if inItem { link = link ?? href } else if feedLink == nil { feedLink = href }
                }
            }
        case "media:thumbnail", "media:content", "enclosure":
            if inItem, image == nil, let u = a["url"] {
                let type = a["type"] ?? a["medium"] ?? ""
                if n == "media:thumbnail" || type.hasPrefix("image") || type == "image" { image = u }
            }
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ p: XMLParser, foundCDATA data: Data) { text += String(decoding: data, as: UTF8.self) }

    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let n = name.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        if inItem {
            switch n {
            case "item", "entry":
                inItem = false
                let raw = link ?? item["link"] ?? item["guid"] ?? item["id"] ?? ""
                guard let url = URL(string: raw, relativeTo: base), url.scheme?.hasPrefix("http") == true else { return }
                let body = item["content:encoded"] ?? item["content"] ?? item["description"] ?? item["summary"] ?? ""
                let firstImage = image ?? Self.firstImage(in: body)
                entries.append(FeedEntry(
                    url: url.absoluteString,
                    title: PreviewFetcher.plain(item["title"] ?? ""),
                    date: FeedParser.Dates.parse(item["pubdate"] ?? item["published"] ?? item["updated"] ?? item["dc:date"]),
                    author: item["dc:creator"] ?? item["author"] ?? item["name"],
                    summary: FeedParser.Text.trim(PreviewFetcher.plain(body)),
                    image: firstImage.flatMap { URL(string: $0, relativeTo: url)?.absoluteString }))
            case "link" where !value.isEmpty: link = link ?? value
            default:
                if !value.isEmpty, item[n] == nil { item[n] = value }
            }
        } else {
            switch n {
            case "title" where feedTitle.isEmpty: feedTitle = PreviewFetcher.plain(value)
            case "link" where feedLink == nil && !value.isEmpty: feedLink = value
            default: break
            }
        }
    }

    private static func firstImage(in html: String) -> String? {
        guard let r = html.range(of: #"<img[^>]+src=["']([^"']+)["']"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tag = String(html[r])
        guard let s = tag.range(of: #"src=["']([^"']+)["']"#, options: .regularExpression) else { return nil }
        return String(tag[s].dropFirst(5).dropLast())
    }
}

// MARK: - Fetching and discovery

enum FeedFetcher {
    enum Result: Sendable {
        case items(FeedParser.Parsed, etag: String?, lastModified: String?)
        case unchanged
        case failed(String)
    }

    /// One conditional GET, paced per site by HostGate.
    static func fetch(_ feed: Feed) async -> Result {
        guard let url = URL(string: feed.url), let host = url.host() else { return .failed("Not a web address") }
        guard await HostGate.shared.admit(host) else { return .failed("\(host) asked Sift to wait") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Sift (feed reader; +https://github.com/michellzappa/sift)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/rss+xml, application/atom+xml, application/feed+json, application/xml;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        if let e = feed.etag { req.setValue(e, forHTTPHeaderField: "If-None-Match") }
        if let m = feed.lastModified { req.setValue(m, forHTTPHeaderField: "If-Modified-Since") }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            switch http?.statusCode ?? 0 {
            case 304: return .unchanged
            case 429, 503:
                await HostGate.shared.pause(host, seconds: 3600)
                return .failed("\(host) is busy; Sift tries again in an hour")
            case 200..<300: break
            case let code: return .failed("The feed answered \(code)")
            }
            guard let parsed = FeedParser.parse(data, base: url) else { return .failed("Not an RSS, Atom or JSON feed") }
            return .items(parsed, etag: http?.value(forHTTPHeaderField: "ETag"), lastModified: http?.value(forHTTPHeaderField: "Last-Modified"))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Finds the feed for a site or page: the URL itself if it is a feed,
    /// else the page's <link rel="alternate">, else the usual paths.
    static func discover(_ input: String) async -> (url: String, parsed: FeedParser.Parsed)? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        if let parsed = FeedParser.parse(data, base: url) { return (url.absoluteString, parsed) }
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        var candidates: [String] = []
        let pattern = #"<link[^>]+rel=["']alternate["'][^>]*>"#
        if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let ns = html as NSString
            for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let tag = ns.substring(with: m.range)
                guard tag.range(of: #"(rss|atom|feed\+json|json)"#, options: [.regularExpression, .caseInsensitive]) != nil,
                      let h = tag.range(of: #"href=["']([^"']+)["']"#, options: .regularExpression) else { continue }
                let href = String(tag[h].dropFirst(6).dropLast()).replacingOccurrences(of: "&amp;", with: "&")
                if let u = URL(string: href, relativeTo: url) { candidates.append(u.absoluteString) }
            }
        }
        let root = url.scheme! + "://" + (url.host() ?? "")
        candidates += ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml", "/index.xml", "/feed.json"].map { root + $0 }
        for c in candidates {
            guard let u = URL(string: c), let (d, r) = try? await URLSession.shared.data(from: u),
                  ((r as? HTTPURLResponse)?.statusCode ?? 0) < 400,
                  let parsed = FeedParser.parse(d, base: u) else { continue }
            return (c, parsed)
        }
        return nil
    }
}
