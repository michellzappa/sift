import Foundation

/// Reads link exports from read-later and bookmark tools into Sift sources:
///
/// - CSV: Instapaper, Pocket, Readwise Reader, Raindrop, Matter and most
///   others. Columns are found by name (url, title, folder or tags, a date).
/// - JSON: Pinboard and other arrays of objects with `href` or `url`.
/// - HTML: the Netscape bookmark file that browsers and most tools export.
///
/// Each imported file is one source. Sift reads the file read-only, each
/// time it loads the source, so importing a newer export is just picking the
/// new file.
enum LinkImporter {
    typealias Item = ReadingListReader.Item

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One imported file, as Sift remembers it.
    struct Source: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var name: String
        var path: String
        var added: Date
    }

    static let sourcePrefix = "import:"

    static func items(at path: String) throws -> [Item] {
        let url = URL(filePath: path)
        // A Google Takeout zip or folder: YouTube playlists, Watch Later first.
        if url.pathExtension.lowercased() == "zip" || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let items = try YouTubeTakeout.items(at: path)
            guard !items.isEmpty else { throw Failure(message: "No YouTube playlists found in \(url.lastPathComponent). Export \"YouTube and YouTube Music\" from Google Takeout with playlists included.") }
            return items
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw Failure(message: "Sift cannot read \(url.lastPathComponent). Move it, then choose it again.")
        }
        let text = String(decoding: data, as: UTF8.self)
        let head = text.prefix(600).lowercased()
        let raw: [Item]
        switch url.pathExtension.lowercased() {
        case "json": raw = try json(data)
        case "html", "htm": raw = html(text)
        case "csv": raw = csv(text)
        default:
            if head.contains("<!doctype netscape-bookmark") || head.contains("<dl") { raw = html(text) }
            else if head.trimmingCharacters(in: .whitespaces).hasPrefix("[") || head.hasPrefix("{") { raw = try json(data) }
            else { raw = csv(text) }
        }
        var seen = Set<String>()
        let unique = raw.filter { seen.insert($0.tab.url).inserted }
        guard !unique.isEmpty else { throw Failure(message: "No links found in \(url.lastPathComponent).") }
        return unique.sorted { ($0.tab.lastViewed ?? .distantPast) > ($1.tab.lastViewed ?? .distantPast) }
    }

    /// A name for the source from the file: "instapaper-export.csv" becomes
    /// "Instapaper".
    static func suggestedName(for path: String) -> String {
        let base = URL(filePath: path).deletingPathExtension().lastPathComponent.lowercased()
        if base.contains("takeout") || base.contains("youtube") { return "YouTube" }
        let known = ["instapaper", "pocket", "readwise", "raindrop", "pinboard", "matter", "omnivore", "chrome", "firefox", "safari", "arc", "bookmarks"]
        if let hit = known.first(where: { base.contains($0) }) { return hit.prefix(1).uppercased() + hit.dropFirst() }
        let words = base.replacingOccurrences(of: #"[_\-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\d{4,}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? "Imported links" : words.prefix(1).uppercased() + words.dropFirst()
    }

    // MARK: Formats

    private static func csv(_ text: String) -> [Item] {
        let rows = CSV.parse(text)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { return [] }
        func column(_ names: [String]) -> Int? { names.lazy.compactMap { n in header.firstIndex(of: n) }.first }
        guard let u = column(["url", "link", "href", "address"]) else { return [] }
        let t = column(["title", "name", "description"])
        let note = column(["selection", "excerpt", "note", "notes", "summary", "highlights"])
        let folder = column(["folder", "collection", "tags", "tag", "list"])
        let date = column(["timestamp", "time_added", "saved date", "saved_at", "created", "date", "added", "time", "created_at"])
        return rows.dropFirst().compactMap { row in
            func cell(_ i: Int?) -> String { i.flatMap { row.indices.contains($0) ? row[$0] : nil }?.trimmingCharacters(in: .whitespaces) ?? "" }
            return item(url: cell(u), title: cell(t), note: cell(note), folder: cell(folder), date: parseDate(cell(date)))
        }
    }

    private static func json(_ data: Data) throws -> [Item] {
        let root = try JSONSerialization.jsonObject(with: data)
        let list: [[String: Any]]
        if let array = root as? [[String: Any]] { list = array }
        else if let dict = root as? [String: Any], let array = (dict["items"] ?? dict["bookmarks"] ?? dict["links"] ?? dict["data"]) as? [[String: Any]] { list = array }
        else { return [] }
        return list.compactMap { o in
            let url = o["href"] as? String ?? o["url"] as? String ?? o["link"] as? String ?? ""
            let title = o["description"] as? String ?? o["title"] as? String ?? o["name"] as? String ?? ""
            let note = o["extended"] as? String ?? o["excerpt"] as? String ?? o["note"] as? String ?? ""
            let tags = (o["tags"] as? String) ?? ((o["tags"] as? [String])?.joined(separator: ", ")) ?? (o["folder"] as? String) ?? ""
            let rawDate = o["time"] ?? o["created"] ?? o["created_at"] ?? o["time_added"] ?? o["date"]
            let date = (rawDate as? String).flatMap(parseDate) ?? (rawDate as? Double).map { Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) }
            return item(url: url, title: title, note: note, folder: tags, date: date)
        }
    }

    /// Netscape bookmark HTML: <DT><A HREF="…" ADD_DATE="…">Title</A>, with
    /// folders as <H3>. The folder path becomes the note.
    private static func html(_ text: String) -> [Item] {
        var out: [Item] = []
        var folders: [String] = []
        let pattern = #"<h3[^>]*>(.*?)</h3>|<a\s([^>]*)>(.*?)</a>|</dl>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 1).location != NSNotFound {
                folders.append(PreviewFetcher.plain(ns.substring(with: m.range(at: 1))))
            } else if m.range(at: 2).location != NSNotFound {
                let attrs = ns.substring(with: m.range(at: 2))
                let title = PreviewFetcher.plain(ns.substring(with: m.range(at: 3)))
                func attr(_ name: String) -> String? {
                    guard let r = attrs.range(of: #"\#(name)\s*=\s*"([^"]*)""#, options: [.regularExpression, .caseInsensitive]) else { return nil }
                    let found = String(attrs[r])
                    return found.split(separator: "\"", maxSplits: 2).dropFirst().first.map(String.init)
                }
                let date = attr("ADD_DATE").flatMap(Double.init).map { Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) }
                if let i = item(url: attr("HREF") ?? "", title: title, note: "", folder: folders.joined(separator: " / "), date: date) {
                    out.append(i)
                }
            } else if !folders.isEmpty {
                folders.removeLast()
            }
        }
        return out
    }

    private static func item(url: String, title: String, note: String, folder: String, date: Date?) -> Item? {
        guard url.hasPrefix("http"), URL(string: url) != nil else { return nil }
        let tab = SafariTab(url: url, title: title, lastViewed: date)
        var text = note
        if !folder.isEmpty { text = text.isEmpty ? "In \(folder)." : "\(text) (in \(folder))" }
        let preview = text.isEmpty ? nil : Preview(title: title, text: String(text.prefix(400)), imageURL: nil, site: tab.host, fetched: date ?? .now)
        return Item(tab: tab, preview: preview)
    }

    private static func parseDate(_ s: String) -> Date? {
        let v = s.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return nil }
        if let n = Double(v) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        if let d = ISO8601DateFormatter().date(from: v) ?? ISO8601DateFormatter.withFractions.date(from: v) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "MMMM d, yyyy", "MM/dd/yyyy"] {
            f.dateFormat = format
            if let d = f.date(from: v) { return d }
        }
        return nil
    }
}

/// Reads YouTube playlists from a Google Takeout export ("YouTube and YouTube
/// Music"): Watch Later and every other playlist CSV under `playlists/`. Each
/// video becomes a link; the playlist name becomes its note. The YouTube API
/// cannot read Watch Later, so Takeout is the only way in.
enum YouTubeTakeout {
    static func items(at path: String) throws -> [LinkImporter.Item] {
        var files: [(name: String, text: String)] = []
        let url = URL(filePath: path)
        if url.pathExtension.lowercased() == "zip" {
            for member in try zipMembers(path) where member.lowercased().contains("/playlists/") && member.lowercased().hasSuffix(".csv") {
                if let text = try? unzipText(path, member) { files.append((URL(filePath: member).deletingPathExtension().lastPathComponent, text)) }
            }
        } else if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let file as URL in walker where file.path.lowercased().contains("/playlists/") && file.pathExtension.lowercased() == "csv" {
                if let text = try? String(contentsOf: file, encoding: .utf8) { files.append((file.deletingPathExtension().lastPathComponent, text)) }
            }
        }
        // Watch Later first, then the other playlists.
        files.sort { a, b in a.name.lowercased().hasPrefix("watch later") && !b.name.lowercased().hasPrefix("watch later") }
        var out: [LinkImporter.Item] = []
        for file in files {
            let playlist = file.name.replacingOccurrences(of: "-videos", with: "").trimmingCharacters(in: .whitespaces)
            var rows = CSV.parse(file.text)
            // Older exports put playlist metadata above a blank line; find the video header.
            if let start = rows.firstIndex(where: { $0.first?.lowercased().replacingOccurrences(of: " ", with: "") == "videoid" }) {
                rows = Array(rows[start...])
            }
            guard let header = rows.first?.map({ $0.lowercased() }), let idColumn = header.firstIndex(where: { $0.replacingOccurrences(of: " ", with: "") == "videoid" }) else { continue }
            let timeColumn = header.firstIndex { $0.contains("time") || $0.contains("added") }
            for row in rows.dropFirst() where row.indices.contains(idColumn) {
                let id = row[idColumn].trimmingCharacters(in: .whitespaces)
                guard id.count >= 8 else { continue }
                let date = timeColumn.flatMap { row.indices.contains($0) ? row[$0] : nil }.flatMap { ISO8601DateFormatter().date(from: $0.trimmingCharacters(in: .whitespaces)) ?? ISO8601DateFormatter.withFractions.date(from: $0.trimmingCharacters(in: .whitespaces)) }
                let tab = SafariTab(url: "https://www.youtube.com/watch?v=\(id)", title: "", lastViewed: date)
                let preview = Preview(title: "", text: "In \(playlist) on YouTube.", imageURL: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg", site: "youtube.com", fetched: date ?? .now)
                out.append(.init(tab: tab, preview: preview))
            }
        }
        return out
    }

    private static func zipMembers(_ zip: String) throws -> [String] {
        String(decoding: try run(["-Z1", zip]), as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private static func unzipText(_ zip: String, _ member: String) throws -> String {
        String(decoding: try runUnzip(["-p", zip, member]), as: UTF8.self)
    }

    private static func run(_ args: [String]) throws -> Data { try runTool("/usr/bin/zipinfo", args) }
    private static func runUnzip(_ args: [String]) throws -> Data { try runTool("/usr/bin/unzip", args) }

    private static func runTool(_ tool: String, _ args: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(filePath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }
}
