import Foundation

/// Reads the saved posts and saved collections from an Instagram data
/// export ("Download your information", JSON format), read-only. The user
/// picks the export once in Settings: the zip as Instagram sends it, or the
/// folder it unpacks to. Sift never writes to it.
///
/// Files: `your_instagram_activity/saved/saved_posts.json` and
/// `saved_collections.json`. A saved post is a list of `label_values`
/// (URL with `href`, Caption, Title, and an "Owner" group with Name,
/// Username and URL) plus `timestamp` (Unix seconds, when it was saved).
/// A collection has Name, Type, Privacy, "Update time" and a "Media" group
/// whose entries have the same shape as a saved post. Older exports use
/// `saved_saved_media` / `saved_saved_collections` with `string_map_data`;
/// both shapes are read.
enum InstagramReader {
    /// The source picker shows Instagram Saved next to the synced devices
    /// under this fixed id.
    static let sourceID = "instagram-saved"

    typealias Item = ReadingListReader.Item

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func items(at path: String) throws -> [Item] {
        let posts = try read("saved_posts.json", in: path)
        let collections = try? read("saved_collections.json", in: path)
        guard let posts else { throw Failure(message: "No saved_posts.json in the export. Request the export in JSON format, not HTML.") }

        // URL -> names of the collections it is in.
        var inCollection: [String: [String]] = [:]
        if let collections {
            for entry in collectionEntries(collections) {
                for url in entry.urls where !(inCollection[url]?.contains(entry.name) ?? false) {
                    inCollection[url, default: []].append(entry.name)
                }
            }
        }

        var seen = Set<String>()
        var out: [Item] = []
        for post in postEntries(posts) {
            guard seen.insert(post.url).inserted else { continue }
            let author = post.name.isEmpty ? (post.username.isEmpty ? "Instagram" : "@\(post.username)") : post.name
            let tab = SafariTab(url: post.url, title: author, lastViewed: post.saved)
            let names = inCollection[post.url] ?? []
            var text = names.isEmpty ? "" : "Saved in \(names.joined(separator: ", ")). "
            text += post.caption
            let preview = Preview(title: author, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                  imageURL: nil, site: "instagram.com", fetched: post.saved ?? .now)
            out.append(Item(tab: tab, preview: preview))
        }
        return out.sorted { ($0.tab.lastViewed ?? .distantPast) > ($1.tab.lastViewed ?? .distantPast) }
    }

    // MARK: Files

    /// The parsed JSON of one saved file, or nil when the export has none.
    private static func read(_ name: String, in path: String) throws -> Any? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            throw Failure(message: "The Instagram export was not found at \(path).")
        }
        let data: Data?
        if isDir.boolValue {
            let root = URL(filePath: path, directoryHint: .isDirectory)
            let candidates = ["your_instagram_activity/saved/\(name)", "saved/\(name)", name]
            data = candidates.lazy.compactMap { FileManager.default.contents(atPath: root.appending(path: $0).path(percentEncoded: false)) }.first
        } else {
            data = try unzip(path, member: "*saved/\(name)")
        }
        guard let data, !data.isEmpty else { return nil }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// One member of the zip, through /usr/bin/unzip. Nil when it is not there.
    private static func unzip(_ zip: String, member: String) throws -> Data? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-p", zip, member]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Read before waiting so a full pipe cannot block the child.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    // MARK: Shapes

    private struct Post {
        var url: String
        var name = ""
        var username = ""
        var caption = ""
        var saved: Date?
    }

    private static func postEntries(_ json: Any) -> [Post] {
        if let list = json as? [[String: Any]] {
            return list.compactMap { post(labelValues: $0["label_values"], timestamp: $0["timestamp"]) }
        }
        // Older shape: {"saved_saved_media": [{"title": username, "string_map_data": {"Saved on": {href, timestamp}}}]}
        guard let list = (json as? [String: Any])?["saved_saved_media"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let saved = (entry["string_map_data"] as? [String: Any])?.values.first as? [String: Any],
                  let url = (saved["href"] as? String).flatMap(canonical) else { return nil }
            return Post(url: url, username: fix(entry["title"] as? String ?? ""), saved: date(saved["timestamp"]))
        }
    }

    private static func collectionEntries(_ json: Any) -> [(name: String, urls: [String])] {
        if let list = json as? [[String: Any]] {
            return list.compactMap { entry in
                let values = entry["label_values"] as? [[String: Any]] ?? []
                guard let name = values.first(where: { $0["label"] as? String == "Name" })?["value"] as? String else { return nil }
                let media = values.first { $0["title"] as? String == "Media" }?["dict"] as? [[String: Any]] ?? []
                let urls = media.compactMap { post(labelValues: $0["dict"], timestamp: nil)?.url }
                return (fix(name), urls)
            }
        }
        // Older shape: a flat list where a "Collection" row starts each
        // collection and the rows after it are its posts.
        guard let list = (json as? [String: Any])?["saved_saved_collections"] as? [[String: Any]] else { return [] }
        var out: [(name: String, urls: [String])] = []
        for entry in list {
            let map = entry["string_map_data"] as? [String: Any] ?? [:]
            let nameField = map["Name"] as? [String: Any]
            if entry["title"] as? String == "Collection", let name = nameField?["value"] as? String {
                out.append((fix(name), []))
            } else if let url = (nameField?["href"] as? String).flatMap(canonical), !out.isEmpty {
                out[out.count - 1].urls.append(url)
            }
        }
        return out
    }

    /// A post from the current shape's `label_values` list.
    private static func post(labelValues: Any?, timestamp: Any?) -> Post? {
        let values = labelValues as? [[String: Any]] ?? []
        guard let href = values.first(where: { $0["label"] as? String == "URL" })?["href"] as? String,
              let url = canonical(href) else { return nil }
        var post = Post(url: url, saved: date(timestamp))
        post.caption = values.lazy.filter { $0["label"] as? String == "Caption" }
            .compactMap { $0["value"] as? String }.first { !$0.isEmpty }.map(fix) ?? ""
        let owner = (values.first { $0["title"] as? String == "Owner" }?["dict"] as? [[String: Any]])?.first?["dict"] as? [[String: Any]] ?? []
        func field(_ label: String) -> String { fix(owner.first { $0["label"] as? String == label }?["value"] as? String ?? "") }
        post.name = field("Name")
        post.username = field("Username")
        return post
    }

    /// `https://www.instagram.com/p/<code>/` or `/reel/<code>/`, without query
    /// or tracking parts, so the same post is one link everywhere.
    private static func canonical(_ href: String) -> String? {
        guard let url = URL(string: href), url.host()?.hasSuffix("instagram.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }), parts.count > i + 1 else { return nil }
        let kind = parts[i] == "reels" ? "reel" : parts[i]
        return "https://www.instagram.com/\(kind)/\(parts[i + 1])/"
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    /// Instagram writes UTF-8 text as one \u00XX escape per byte, so "é"
    /// arrives as "Ã©". When every character fits in one byte, read those
    /// bytes again as UTF-8. Text that is not valid UTF-8 that way is kept.
    static func fix(_ s: String) -> String {
        let scalars = s.unicodeScalars
        guard scalars.contains(where: { $0.value > 0x7F }), scalars.allSatisfy({ $0.value <= 0xFF }) else { return s }
        return String(bytes: scalars.map { UInt8($0.value) }, encoding: .utf8) ?? s
    }
}
