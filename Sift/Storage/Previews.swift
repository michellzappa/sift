import Foundation

/// What Sift knows about a page beyond its tab title.
struct Preview: Codable, Hashable, Sendable {
    var title: String
    var text: String
    var imageURL: String?
    var site: String
    var fetched: Date
    var failed: Bool = false
}

/// Fetches previews and keeps them in ~/Library/Application Support/Sift/previews.json.
/// X posts come from X's public oEmbed endpoint, which returns the post text
/// without a login. Other pages come from their HTML: Open Graph tags first,
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

    static func fetch(_ urlString: String) async -> Preview {
        guard let url = URL(string: urlString) else { return failed(urlString) }
        if isXPost(url), let p = await oEmbed(url) { return p }
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
