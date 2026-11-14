import Foundation

/// What Sift knows about a page beyond its tab title.
struct Preview: Codable, Hashable, Sendable {
    var title: String
    var text: String
    var imageURL: String?
    var site: String
    var fetched: Date
    var failed: Bool = false
    /// Author avatar for X posts. Only the syndication endpoint returns it.
    var avatarURL: String? = nil

    init(title: String, text: String, imageURL: String?, site: String, fetched: Date, failed: Bool = false, avatarURL: String? = nil) {
        self.title = title
        self.text = text
        self.imageURL = imageURL
        self.site = site
        self.fetched = fetched
        self.failed = failed
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        site = try c.decode(String.self, forKey: .site)
        fetched = try c.decode(Date.self, forKey: .fetched)
        failed = try c.decodeIfPresent(Bool.self, forKey: .failed) ?? false
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
    }
}

/// Fetches previews and keeps them in ~/Library/Application Support/Sift/previews.json.
/// X posts come from X's public oEmbed endpoint, which returns the post text
/// without a login. When the user turns on the opt-in setting, X posts first
/// try X's syndication endpoint (the one X's embedded posts use), which also
/// returns images. It is unofficial and can stop working; oEmbed is the fallback. Other pages come from their HTML: Open Graph tags first,
/// then <title> and the meta description.
enum PreviewFetcher {
    static var cacheURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "previews.json") }

    static func loadCache() -> [String: Preview] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Preview].self, from: data)) ?? [:]
    }

    static func saveCache(_ cache: [String: Preview]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    static func fetch(_ urlString: String, xSyndication: Bool = false) async -> Preview {
        guard let url = URL(string: urlString) else { return failed(urlString) }
        if isXPost(url) {
            if xSyndication, let p = await syndication(url) { return p }
            if let p = await oEmbed(url) { return p }
        }
        return await html(url) ?? failed(urlString)
    }

    static func isXPost(_ url: URL) -> Bool {
        let host = url.host() ?? ""
        return ["x.com", "twitter.com", "mobile.twitter.com", "www.x.com"].contains(host) && url.path().contains("/status/")
    }

    private static func failed(_ url: String) -> Preview {
        Preview(title: "", text: "", imageURL: nil, site: URL(string: url)?.host() ?? "", fetched: .now, failed: true)
    }

    private static func oEmbed(_ url: URL) async -> Preview? {
        // Strip /photo/1 and query noise; oEmbed wants the bare status URL.
        var parts = url.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(of: "status"), parts.count > i + 1 { parts = Array(parts[...(i + 1)]) }
        let clean = "https://x.com/" + parts.joined(separator: "/")
        var c = URLComponents(string: "https://publish.twitter.com/oembed")!
        c.queryItems = [.init(name: "url", value: clean), .init(name: "omit_script", value: "1"), .init(name: "dnt", value: "true")]
        guard let endpoint = c.url,
              let (data, response) = try? await URLSession.shared.data(from: endpoint),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = json["html"] as? String
        else { return nil }
        // The post text is the first <p> in the blockquote.
        let paragraph = html.range(of: #"<p[^>]*>(.*?)</p>"#, options: .regularExpression).map { String(html[$0]) } ?? html
        let author = json["author_name"] as? String ?? "X"
        return Preview(title: author, text: plain(paragraph), imageURL: nil, site: "x.com", fetched: .now)
    }

    /// X's syndication endpoint (cdn.syndication.twimg.com), as used by X's
    /// embedded posts and react-tweet. Unofficial: off unless the user opts in.
    private static func syndication(_ url: URL) async -> Preview? {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "status"), parts.count > i + 1,
              let id = Double(parts[i + 1]), parts[i + 1].allSatisfy(\.isNumber)
        else { return nil }
        var c = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        c.queryItems = [.init(name: "id", value: parts[i + 1]), .init(name: "token", value: syndicationToken(id)), .init(name: "lang", value: "en")]
        guard let endpoint = c.url,
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: endpoint, timeoutInterval: 15)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["__typename"] as? String != "TweetTombstone",
              let text = json["text"] as? String
        else { return nil }
        let user = json["user"] as? [String: Any]
        let photo = (json["photos"] as? [[String: Any]])?.first?["url"] as? String
        let media = (json["mediaDetails"] as? [[String: Any]])?.first?["media_url_https"] as? String
        let poster = (json["video"] as? [String: Any])?["poster"] as? String
        return Preview(
            title: user?["name"] as? String ?? "X",
            text: plain(text),
            imageURL: photo ?? media ?? poster,
            site: "x.com",
            fetched: .now,
            avatarURL: (user?["profile_image_url_https"] as? String)?.replacingOccurrences(of: "_normal.", with: "_bigger.")
        )
    }

    /// The token react-tweet sends: `((id / 1e15) * Math.PI).toString(36)`
    /// with every run of zeros and the dot removed.
    static func syndicationToken(_ id: Double) -> String {
        jsRadixString((id / 1e15) * Double.pi, radix: 36)
            .replacingOccurrences(of: "(0+|\\.)", with: "", options: .regularExpression)
    }

    /// Port of V8's DoubleToRadixCString (Number.prototype.toString(radix))
    /// for positive finite values of normal size.
    private static func jsRadixString(_ value: Double, radix: Int) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let r = Double(radix)
        var integer = value.rounded(.down)
        var fraction = value - integer
        var delta = max(0.5 * (value.nextUp - value), Double.leastNonzeroMagnitude)
        var digits: [Int] = []
        if fraction >= delta {
            repeat {
                fraction *= r
                delta *= r
                let digit = Int(fraction)
                digits.append(digit)
                fraction -= Double(digit)
                if fraction > 0.5 || (fraction == 0.5 && digit & 1 == 1), fraction + delta > 1 {
                    // Round up, carrying over written digits.
                    while true {
                        guard let last = digits.popLast() else { integer += 1; break }
                        if last + 1 < radix { digits.append(last + 1); break }
                    }
                    break
                }
            } while fraction >= delta
        }
        var intDigits: [Character] = []
        repeat {
            let remainder = integer.truncatingRemainder(dividingBy: r)
            intDigits.insert(chars[Int(remainder)], at: 0)
            integer = (integer - remainder) / r
        } while integer > 0
        return String(intDigits) + (digits.isEmpty ? "" : "." + String(digits.map { chars[$0] }))
    }

    private static func html(_ url: URL) async -> Preview? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              (http.value(forHTTPHeaderField: "Content-Type") ?? "text/html").contains("html")
        else { return nil }
        let head = String(decoding: data.prefix(600_000), as: UTF8.self)
        let title = meta(head, "og:title") ?? tag(head, "title") ?? ""
        let text = meta(head, "og:description") ?? meta(head, "description") ?? meta(head, "twitter:description") ?? ""
        var image = meta(head, "og:image") ?? meta(head, "twitter:image")
        if let i = image, let resolved = URL(string: i, relativeTo: url) { image = resolved.absoluteString }
        let site = meta(head, "og:site_name") ?? (url.host() ?? "")
        if title.isEmpty && text.isEmpty { return nil }
        return Preview(title: plain(title), text: plain(text), imageURL: image, site: site, fetched: .now)
    }

    /// Content of <meta property|name="key" content="…"> in either attribute order.
    private static func meta(_ html: String, _ key: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            #"<meta[^>]+(?:property|name)\s*=\s*["']"# + k + #"["'][^>]*content\s*=\s*["']([^"']*)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*(?:property|name)\s*=\s*["']"# + k + #"["']"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html) {
                let v = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { return v }
            }
        }
        return nil
    }

    private static func tag(_ html: String, _ name: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<\(name)[^>]*>(.*?)</\(name)>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html)
        else { return nil }
        return String(html[r])
    }

    /// Strips tags and decodes the common HTML entities.
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<br ?/?>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);") {
            let ns = t as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let code = ns.substring(with: m.range(at: 1))
                let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
                out += value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            t = out
        }
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The close list the iPhone Shortcut reads: one URL per line in
/// iCloud Drive/Sift/close.txt.
enum CloseList {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Sift", directoryHint: .isDirectory)
    }

    static var fileURL: URL { folder.appending(path: "close.txt") }

    static var iCloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path(percentEncoded: false))
    }

    /// Creates an empty close.txt if there is none. Never empties an existing list.
    static func ensureExists() {
        guard iCloudDriveAvailable, !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        write([])
    }

    static func write(_ urls: [String]) {
        guard iCloudDriveAvailable else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = urls.sorted().joined(separator: "\n") + (urls.isEmpty ? "" : "\n")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
