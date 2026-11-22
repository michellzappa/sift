import Foundation

/// Reads favourite (and, on request, liked) videos from a TikTok data export
/// ("Download your data", JSON format), read-only. The user picks the export
/// once in Settings: the zip as TikTok sends it, or the folder it unpacks to.
/// Sift never writes to it.
///
/// The export is one JSON file (`user_data_tiktok.json`, older exports
/// `user_data.json`). TikTok has moved its sections between versions, so
/// the reader walks the whole tree and takes the lists by their names:
/// `FavoriteVideoList` (favourites) and `ItemFavoriteList` (likes). Each
/// entry has a date ("2024-05-01 12:34:56", UTC) and a link, with the key
/// in any case ("Date"/"date", "Link"/"link"/"VideoLink").
enum TikTokReader {
    static let sourceID = "tiktok"

    typealias Item = ReadingListReader.Item

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Counts: Equatable { var favorites = 0, likes = 0 }

    /// Favourites, plus likes when `likes` is true. Newest first, each video once.
    static func items(at path: String, likes: Bool) throws -> (items: [Item], counts: Counts) {
        let json = try read(path)
        var favorites: [[String: Any]] = []
        var liked: [[String: Any]] = []
        walk(json) { key, list in
            if key == "FavoriteVideoList" { favorites += list }
            if key == "ItemFavoriteList" { liked += list }
        }
        var counts = Counts(favorites: favorites.count, likes: liked.count)
        if favorites.isEmpty && liked.isEmpty {
            throw Failure(message: "No favourite or liked videos in the export. Request the export in JSON format, not TXT.")
        }
        var seen = Set<String>()
        var out: [Item] = []
        func add(_ entries: [[String: Any]], liked: Bool) {
            for entry in entries {
                guard let link = value(entry, ["link", "videolink", "url"]), let url = canonical(link),
                      seen.insert(url).inserted else { continue }
                let date = value(entry, ["date"]).flatMap(parseDate)
                let tab = SafariTab(url: url, title: "", lastViewed: date)
                let note = liked ? "Liked on TikTok." : "Favourite on TikTok."
                let preview = Preview(title: "", text: note, imageURL: nil, site: "tiktok.com", fetched: .distantPast)
                out.append(Item(tab: tab, preview: preview))
            }
        }
        add(favorites, liked: false)
        if likes { add(liked, liked: true) } else { counts.likes = liked.count }
        out.sort { ($0.tab.lastViewed ?? .distantPast) > ($1.tab.lastViewed ?? .distantPast) }
        return (out, counts)
    }

    // MARK: Links

    /// The video id in any TikTok video link: www.tiktok.com/@user/video/<id>,
    /// www.tiktokv.com/share/video/<id>/, m.tiktok.com/v/<id>.html.
    static func videoID(_ url: String) -> String? {
        guard let u = URL(string: url), let host = u.host()?.lowercased(),
              host.hasSuffix("tiktok.com") || host.hasSuffix("tiktokv.com") else { return nil }
        let parts = u.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(where: { $0 == "video" || $0 == "v" }), parts.count > i + 1 {
            let id = parts[i + 1].replacingOccurrences(of: ".html", with: "")
            if !id.isEmpty, id.allSatisfy(\.isNumber) { return id }
        }
        return nil
    }

    /// `https://www.tiktok.com/@/video/<id>`: TikTok opens it without the
    /// user name, and the same video is one link everywhere. Short links
    /// (vm.tiktok.com) have no id and stay as they are.
    static func canonical(_ link: String) -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: trimmed), let host = u.host()?.lowercased(),
              host.hasSuffix("tiktok.com") || host.hasSuffix("tiktokv.com") else { return nil }
        if let id = videoID(trimmed) { return "https://www.tiktok.com/@/video/\(id)" }
        return trimmed
    }

    // MARK: Files

    static func read(_ path: String) throws -> Any {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            throw Failure(message: "The TikTok export was not found at \(path).")
        }
        let names = ["user_data_tiktok.json", "user_data.json"]
        var data: Data?
        if isDir.boolValue {
            let root = URL(filePath: path, directoryHint: .isDirectory)
            data = names.lazy.compactMap { FileManager.default.contents(atPath: root.appending(path: $0).path(percentEncoded: false)) }.first
        } else if path.lowercased().hasSuffix(".json") {
            data = FileManager.default.contents(atPath: path)
        } else {
            for name in names {
                if let d = try ExportFile.unzip(path, member: "*\(name)"), !d.isEmpty { data = d; break }
            }
        }
        guard let data, !data.isEmpty else {
            throw Failure(message: "No user_data_tiktok.json in the export. Request the export in JSON format, not TXT.")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: Shapes

    /// Calls `found` for every list of objects in the tree, with its key.
    static func walk(_ node: Any, key: String = "", _ found: (String, [[String: Any]]) -> Void) {
        if let dict = node as? [String: Any] {
            for (k, v) in dict { walk(v, key: k, found) }
        } else if let list = node as? [Any] {
            let objects = list.compactMap { $0 as? [String: Any] }
            if !objects.isEmpty { found(key, objects) }
        }
    }

    static func value(_ entry: [String: Any], _ keys: [String]) -> String? {
        for (k, v) in entry where keys.contains(k.lowercased()) {
            if let s = v as? String, !s.isEmpty { return s }
        }
        return nil
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)
    }
}
