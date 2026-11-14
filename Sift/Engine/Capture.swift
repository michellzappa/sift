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
    /// Videos: length in seconds.
    var duration: Int? = nil
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
    enum Outcome: Sendable {
        case captured(Capture)
        /// The page is gone: 404 or 410, or its site no longer exists.
        case gone
        /// Anything else: a timeout, a login wall, a blocked fetch, a paused site.
        case failed
    }

    private struct Gone: Error {}

    static func capture(_ urlString: String, knownText: String? = nil) async -> Outcome {
        do {
            if let c = try await extract(urlString, knownText: knownText) { return .captured(c) }
            return .failed
        } catch {
            return .gone
        }
    }

    private static func extract(_ urlString: String, knownText: String?) async throws -> Capture? {
        guard let url = URL(string: urlString) else { return nil }
        if let knownText, !knownText.isEmpty {
            return Capture(url: urlString, title: "", author: nil, site: url.host() ?? "", published: nil, kind: "post", text: knownText)
        }
        // One site at a time, politely; a paused site is skipped, not failed.
        let host = (url.host() ?? "").lowercased()
        guard await HostGate.shared.admit(host) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let e as URLError where e.code == .cannotFindHost || e.code == .dnsLookupFailed {
            throw Gone()
        } catch {
            return nil
        }
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 || http.statusCode == 410 { throw Gone() }
        if http.statusCode == 429 || http.statusCode == 503 {
            await HostGate.shared.pause(host, seconds: 3600)
            return nil
        }
        guard (200..<400).contains(http.statusCode) else { return nil }
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
        if site.hasSuffix("youtube.com") || site == "youtu.be" { return YouTubePage.capture(html: html, url: urlString) }
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
        /// ok, thin (too little text: paywall or login), failed, gone (404,
        /// 410 or the site no longer exists)
        var status: String
        /// YouTube only: true when a transcript is in the file, false when
        /// the video has none, nil when not tried yet.
        var transcript: Bool?
        /// On-device summary (`LocalModel.summarize`), also in the file's
        /// front matter as `summary:`. Nil: not tried yet; "": the model
        /// declined this text.
        var summary: String?
        /// Videos: length in seconds.
        var duration: Int?
    }

    static var folder: URL {
        let dir = StateFile.url.deletingLastPathComponent().appending(path: "Library", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var indexURL: URL { folder.appending(path: "index.json") }

    static func loadIndex() -> [String: Entry] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return SafeStore.load(indexURL, as: [String: Entry].self, decoder: d) ?? [:]
    }

    static func saveIndex(_ index: [String: Entry]) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(index) else { return }
        SafeStore.save(data, to: indexURL)
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
        if let d = c.duration { lines.append("duration: \(d)") }
        if let theme { lines.append("theme: \(y(theme))") }
        lines += ["source: \(y(source))", "captured: \(ISO8601DateFormatter().string(from: .now))", "words: \(c.words)", "---", "", c.text, ""]
        try? lines.joined(separator: "\n").write(to: folder.appending(path: file), atomically: true, encoding: .utf8)
        // Posts are short by nature; only articles and PDFs can be "thin".
        let thin = c.kind != "post" && c.kind != "video" && c.words < 150
        var entry = Entry(file: file, captured: .now, words: c.words, kind: c.kind, status: thin ? "thin" : "ok")
        entry.duration = c.duration
        return entry
    }

    /// Adds a transcript to the link's library file: appended under a
    /// "## Transcript" heading when the page was captured, otherwise a new
    /// file with the transcript alone.
    /// - Parameter heard: true when Sift transcribed the audio itself (no
    ///   captions); the heading says so.
    static func addTranscript(_ text: String, to r: ArchiveRecord, existing: Entry?, heard: Bool = false) -> Entry {
        let heading = heard ? "## Transcript (from the audio, by macOS speech recognition)" : "## Transcript"
        if let existing, !existing.file.isEmpty,
           var raw = try? String(contentsOf: folder.appending(path: existing.file), encoding: .utf8) {
            raw += "\n\(heading)\n\n" + text + "\n"
            try? raw.write(to: folder.appending(path: existing.file), atomically: true, encoding: .utf8)
            var e = existing
            e.words += text.split { $0 == " " || $0 == "\n" }.count
            e.transcript = true
            // The summary is written again with the transcript.
            e.summary = nil
            if e.status == "failed" || e.status == "thin" { e.status = "ok" }
            return e
        }
        let site = URL(string: r.url)?.host() ?? ""
        var e = write(Capture(url: r.url, title: r.title, author: nil, site: site, published: nil, kind: "video",
                              text: heading + "\n\n" + text), title: r.title, theme: r.theme, source: r.source)
        e.transcript = true
        return e
    }

    /// Writes the summary into the file's front matter as `summary:`,
    /// replacing an earlier one.
    static func setSummary(_ summary: String, file: String) {
        let path = folder.appending(path: file)
        guard !file.isEmpty, let raw = try? String(contentsOf: path, encoding: .utf8), raw.hasPrefix("---\n"),
              let end = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 3)..<raw.endIndex)
        else { return }
        var front = raw[raw.index(raw.startIndex, offsetBy: 4)..<end.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("summary:") }
            .map(String.init)
        front.append("summary: \(ExportText.yaml(summary))")
        let out = "---\n" + front.joined(separator: "\n") + "\n---\n" + raw[end.upperBound...]
        try? out.write(to: path, atomically: true, encoding: .utf8)
    }

    /// The captured text (without front matter), if any.
    static func text(for url: String) -> String? {
        guard let raw = try? String(contentsOf: folder.appending(path: fileName(for: url)), encoding: .utf8) else { return nil }
        guard raw.hasPrefix("---"), let end = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 3)..<raw.endIndex) else { return raw }
        return String(raw[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A YouTube video page: title, channel, publish date and the full
/// description (which usually carries the chapter list) from the page's own
/// player data. Transcripts are not captured: YouTube serves captions only to
/// its own player and to a video's owner.
enum YouTubePage {
    static func capture(html: String, url: String) -> Capture? {
        func field(_ key: String) -> String? {
            guard let r = html.range(of: "\"\(key)\":\"") else { return nil }
            var out = ""
            var escaped = false
            for ch in html[r.upperBound...] {
                if escaped { out.append(ch == "n" ? "\n" : ch); escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if ch == "\"" { break }
                out.append(ch)
            }
            return out.isEmpty ? nil : out
        }
        // The page title from Open Graph; the player JSON has many "title" keys.
        let og = html.range(of: #"<meta property="og:title" content="([^"]*)""#, options: .regularExpression).map { String(html[$0]) }
        let title = og.flatMap { $0.components(separatedBy: "content=\"").last?.dropLast().description }.map(PreviewFetcher.plain) ?? field("title") ?? ""
        let channel = field("ownerChannelName") ?? field("author")
        let published = field("publishDate")
        guard let description = field("shortDescription") ?? (title.isEmpty ? nil : "") else { return nil }
        var text = ""
        if let channel { text += "Video by \(channel).\n\n" }
        text += description.replacingOccurrences(of: "\\u0026", with: "&")
        return Capture(url: url, title: title, author: channel, site: "youtube.com", published: published, kind: "video", text: text,
                       duration: field("lengthSeconds").flatMap(Int.init))
    }
}

/// Paces requests per site so capture never floods one site: big sites with
/// many links (YouTube, Instagram, X) get one request every few seconds,
/// others one a second. When a site answers "too many requests", its links
/// are skipped for an hour and retried later instead of marked failed.
actor HostGate {
    static let shared = HostGate()
    private var next: [String: Date] = [:]
    private var pausedUntil: [String: Date] = [:]

    func isPaused(_ host: String) -> Bool { (pausedUntil[host] ?? .distantPast) > .now }

    func pause(_ host: String, seconds: TimeInterval) { pausedUntil[host] = Date().addingTimeInterval(seconds) }

    /// Waits for this site's turn. False when the site is paused.
    func admit(_ host: String) async -> Bool {
        if isPaused(host) { return false }
        let now = Date()
        let at = max(now, next[host] ?? now)
        next[host] = at.addingTimeInterval(interval(host))
        let wait = at.timeIntervalSince(now)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        return !isPaused(host)
    }

    private func interval(_ host: String) -> TimeInterval {
        ["youtube.com", "youtu.be", "instagram.com", "x.com", "twitter.com"].contains { host.hasSuffix($0) } ? 4 : 1
    }
}
