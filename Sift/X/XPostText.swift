import Foundation

/// An X post as Sift keeps it, never from x.com's page (without JavaScript
/// that page is a shell of "enable JavaScript" and CSS). The post comes from
/// the X API when the user connected their own app, else from the preview
/// (oEmbed, or the opt-in syndication endpoint). The handle comes from the
/// URL and the date from the post id, so both are known without a request.
enum XPostText {
    /// The @handle in x.com/<handle>/status/<id>; nil for /i/web/status links.
    static func handle(_ url: String) -> String? {
        guard XClient.statusID(url) != nil, let u = URL(string: url) else { return nil }
        let parts = u.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(of: "status"), i >= 1 else { return nil }
        let h = parts[i - 1]
        return ["i", "web"].contains(h) ? nil : h
    }

    /// When the post was made: post ids since late 2010 carry the time in
    /// their top bits (milliseconds since X's epoch).
    static func date(_ url: String) -> Date? {
        guard let id = XClient.statusID(url).flatMap(UInt64.init), id > 30_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: Double((id >> 22) + 1_288_834_974_657) / 1000)
    }

    /// The post a preview describes, for `XPostView` and the library. Nil
    /// when the preview has no post text.
    static func post(url: String, preview: Preview) -> XPost? {
        guard let id = XClient.statusID(url), !preview.failed, !preview.text.isEmpty, !ShellText.isJunk(preview.text) else { return nil }
        let username = handle(url) ?? "i"
        let name = preview.title.isEmpty || preview.title == "X" ? (handle(url) ?? "X") : preview.title
        let media = [preview.imageURL].compactMap { $0 }.filter { $0.hasPrefix("http") }
            .map { XPost.Media(type: "photo", url: $0, preview: nil, video: nil, alt: nil, width: nil, height: nil) }
        return XPost(id: id, text: preview.text, created: date(url),
                     author: XPost.Author(id: "", name: name, username: username, avatar: preview.avatarURL),
                     media: media, links: links(in: preview.text, expanded: preview.links ?? []),
                     mentions: [], tags: [], quotedID: nil, replyTo: nil, edited: false, fetched: preview.fetched)
    }

    /// Links in preview text (shown as display URLs), as entities with
    /// code point offsets, pointing at the expanded URL when one matches.
    private static func links(in text: String, expanded: [String]) -> [XPost.Link] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let r = Range(m.range, in: text), let found = m.url else { return nil }
            let shown = String(text[r])
            let stem = shown.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            let target = expanded.first { $0.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "www.", with: "").hasPrefix(stem.replacingOccurrences(of: "www.", with: "")) }
                ?? found.absoluteString
            let start = text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: r.lowerBound)
            let end = text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: r.upperBound)
            return XPost.Link(start: start, end: end, tco: target, display: shown, expanded: target, title: nil, summary: nil, isMedia: false)
        }
    }

    /// The post as library Markdown: who and when, the text with its links,
    /// then its pictures.
    static func markdown(_ post: XPost) -> String {
        var head = "**\(post.author?.name ?? "X")**"
        if let u = post.author?.username, u != "i" { head += " @\(u)" }
        if let created = post.created { head += " · " + created.formatted(.iso8601.year().month().day()) }
        var body = ""
        let text = XPostView.attributed(post)
        for run in text.runs {
            let s = String(text[run.range].characters)
            if let link = run.link { body += "[\(s)](\(link.absoluteString))" } else { body += s }
        }
        var blocks = [head, body]
        blocks += post.media.compactMap { $0.url ?? $0.preview }.map { "![Image](\($0))" }
        return blocks.joined(separator: "\n\n")
    }

    /// - Parameter url: the saved link (the library file is named after it).
    static func capture(_ post: XPost, url: String) -> Capture {
        let name = post.author?.name ?? "X"
        return Capture(url: url, title: "\(name) on X", author: name, site: "x.com",
                       published: post.created.map { ISO8601DateFormatter().string(from: $0) }, kind: "post", text: markdown(post))
    }
}
