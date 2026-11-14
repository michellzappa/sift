import CryptoKit
import Foundation
import PDFKit

/// One captured page: the readable text of a link, plus what is known about
/// it. Saved as Markdown in the library (see `Library`).
struct Capture: Sendable {
    var url: String
    var title: String
    var author: String?
    var site: String
    var published: String?
    var kind: String            // article, pdf, post, page
    var text: String            // Markdown
    var words: Int { text.split { $0 == " " || $0 == "\n" }.count }
}

/// Fetches a link once and extracts its readable text, locally, with no
/// Claude involved:
/// - HTML: the main content (article or main element when present), with
///   headings, paragraphs and list items kept as Markdown; navigation,
///   scripts, styles, headers, footers, forms and asides removed.
/// - PDF: the document text through PDFKit.
/// - X posts: the post text Sift already has.
enum Capturer {
    static func capture(_ urlString: String, knownText: String? = nil) async -> Capture? {
        guard let url = URL(string: urlString) else { return nil }
        if let knownText, !knownText.isEmpty {
            return Capture(url: urlString, title: "", author: nil, site: url.host() ?? "", published: nil, kind: "post", text: knownText)
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode)
        else { return nil }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let site = (url.host() ?? "").replacingOccurrences(of: "www.", with: "")
        if type.contains("pdf") || url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(data: data), let text = doc.string, !text.isEmpty else { return nil }
            let title = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? url.lastPathComponent
            let author = doc.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
            return Capture(url: urlString, title: title, author: author, site: site, published: nil, kind: "pdf",
                           text: String(text.prefix(400_000)))
        }
        guard type.isEmpty || type.contains("html") || type.contains("xml") || type.contains("text") else { return nil }
        let html = String(decoding: data.prefix(3_000_000), as: UTF8.self)
        return Readable.extract(html: html, url: urlString, site: site)
    }
}

/// A small readability pass: regular expressions only, no dependencies.
enum Readable {
    static func extract(html: String, url: String, site: String) -> Capture? {
        let title = meta(html, "og:title") ?? tag(html, "title").map(PreviewFetcher.plain) ?? ""
        let author = meta(html, "author") ?? meta(html, "article:author") ?? meta(html, "twitter:creator")
        let published = meta(html, "article:published_time") ?? meta(html, "date") ?? meta(html, "pubdate")
        var body = html
        // Prefer the article or main element when the page has one.
        for container in ["article", "main"] {
            if let inner = largest(container, in: html), inner.count > 1500 { body = inner; break }
        }
        if body == html, let b = tag(html, "body") { body = b }
        // Drop what is never content.
        for noise in ["script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "figure", "iframe", "button", "template"] {
            body = body.replacingOccurrences(of: "<\(noise)\\b[^>]*>.*?</\(noise)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        body = body.replacingOccurrences(of: "<!--.*?-->", with: " ", options: .regularExpression)
        // Keep structure as Markdown.
        body = body.replacingOccurrences(of: "<h1[^>]*>", with: "\n\n# ", options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<h2[^>]*>", with: "\n\n## ", options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<h[3-6][^>]*>", with: "\n\n### ", options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<li[^>]*>", with: "\n- ", options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<blockquote[^>]*>", with: "\n\n> ", options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "</(p|div|section|h[1-6]|ul|ol|blockquote|tr|table)>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        body = body.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        // Strip the remaining tags, decode entities, tidy whitespace, line by line.
        let lines = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { line -> String in
                let lead = line.trimmingCharacters(in: .whitespaces)
                let prefix = ["### ", "## ", "# ", "- ", "> "].first { lead.hasPrefix($0) } ?? ""
                let rest = PreviewFetcher.plain(String(lead.dropFirst(prefix.count)))
                return rest.isEmpty ? "" : prefix + rest
            }
        // Keep headings and lines that read like sentences; drop menu crumbs.
        var kept: [String] = []
        for line in lines where !line.isEmpty {
            let isHeading = line.hasPrefix("#")
            let isItem = line.hasPrefix("- ") || line.hasPrefix("> ")
            if isHeading || (isItem && line.count > 25) || line.count > 60 { kept.append(line) }
        }
        let text = kept.joined(separator: "\n\n")
        guard text.count > 200 else { return nil }
        return Capture(url: url, title: title, author: author, site: site, published: published, kind: "article",
                       text: String(text.prefix(400_000)))
    }

    private static func largest(_ name: String, in html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>(.*?)</\(name)>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
            .max { $0.count < $1.count }
    }

    private static func tag(_ html: String, _ name: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>(.*?)</\(name)>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html)
        else { return nil }
        return String(html[r])
    }

    private static func meta(_ html: String, _ key: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        for p in [#"<meta[^>]+(?:property|name)\s*=\s*["']"# + k + #"["'][^>]*content\s*=\s*["']([^"']*)["']"#,
                  #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*(?:property|name)\s*=\s*["']"# + k + #"["']"#] {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html) {
                let v = PreviewFetcher.plain(String(html[r]))
                if !v.isEmpty { return v }
            }
        }
        return nil
    }
}

/// The library: one Markdown file per captured link, with YAML front matter,
/// in ~/Library/Application Support/Sift/Library/, plus `index.json`.
/// Plain files on purpose: readable without Sift, ready for Obsidian, and the
/// base for digests and search later.
enum Library {
    struct Entry: Codable, Sendable {
        var file: String
        var captured: Date
        var words: Int
        var kind: String
        /// ok, thin (too little text: paywall or login), failed
        var status: String
    }

    static var folder: URL {
        let dir = StateFile.url.deletingLastPathComponent().appending(path: "Library", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var indexURL: URL { folder.appending(path: "index.json") }

    static func loadIndex() -> [String: Entry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [:] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([String: Entry].self, from: data)) ?? [:]
    }

    static func saveIndex(_ index: [String: Entry]) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    static func fileName(for url: String) -> String {
        let hash = Insecure.SHA1.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hash.prefix(16)) + ".md"
    }

    /// Writes the capture as Markdown with front matter. Returns the entry.
    static func write(_ c: Capture, title: String, theme: String?, source: String) -> Entry {
        let file = fileName(for: c.url)
        func y(_ s: String) -> String { ExportText.yaml(s) }
        var lines = ["---", "url: \(y(c.url))", "title: \(y(title.isEmpty ? c.title : title))", "site: \(y(c.site))", "kind: \(c.kind)"]
        if let a = c.author, !a.isEmpty { lines.append("author: \(y(a))") }
        if let p = c.published, !p.isEmpty { lines.append("published: \(y(p))") }
        if let theme { lines.append("theme: \(y(theme))") }
        lines += ["source: \(y(source))", "captured: \(ISO8601DateFormatter().string(from: .now))", "words: \(c.words)", "---", "", c.text, ""]
        try? lines.joined(separator: "\n").write(to: folder.appending(path: file), atomically: true, encoding: .utf8)
        return Entry(file: file, captured: .now, words: c.words, kind: c.kind, status: c.words < 150 ? "thin" : "ok")
    }

    /// The captured text (without front matter), if any.
    static func text(for url: String) -> String? {
        guard let raw = try? String(contentsOf: folder.appending(path: fileName(for: url)), encoding: .utf8) else { return nil }
        guard raw.hasPrefix("---"), let end = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 3)..<raw.endIndex) else { return raw }
        return String(raw[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
