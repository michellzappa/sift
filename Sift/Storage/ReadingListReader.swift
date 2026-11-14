import Foundation

/// Reads Safari's Reading List from ~/Library/Safari/Bookmarks.plist,
/// read-only. Safari owns the file and rewrites it while running, so Sift
/// never writes to it.
enum ReadingListReader {
    /// The source picker shows the Reading List next to the synced devices
    /// under this fixed id.
    static let sourceID = "reading-list"

    static var fileURL: URL {
        if Demo.isOn { return Demo.folder.appending(path: "Bookmarks.plist") }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari/Bookmarks.plist")
    }

    struct Item: Sendable {
        let tab: SafariTab
        let preview: Preview?
    }

    static func items() throws -> [Item] {
        let path = fileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        guard let data = FileManager.default.contents(atPath: path) else { throw CloudTabsReader.Failure.noAccess }
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        guard let list = findReadingList(root) else { return [] }

        var seen = Set<String>()
        var out: [Item] = []
        for case let entry as [String: Any] in list {
            guard let url = entry["URLString"] as? String, seen.insert(url).inserted else { continue }
            let title = (entry["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
            let meta = entry["ReadingList"] as? [String: Any]
            let added = meta?["DateAdded"] as? Date
            let text = meta?["PreviewText"] as? String ?? ""
            let image = entry["imageURL"] as? String
            let tab = SafariTab(url: url, title: title, lastViewed: added)
            let preview = text.isEmpty && image == nil ? nil
                : Preview(title: title, text: text, imageURL: image, site: tab.host, fetched: added ?? .now)
            out.append(Item(tab: tab, preview: preview))
        }
        return out.sorted { ($0.tab.lastViewed ?? .distantPast) > ($1.tab.lastViewed ?? .distantPast) }
    }

    private static func findReadingList(_ node: [String: Any]) -> [Any]? {
        if node["Title"] as? String == "com.apple.ReadingList" { return node["Children"] as? [Any] ?? [] }
        for case let child as [String: Any] in node["Children"] as? [Any] ?? [] {
            if let found = findReadingList(child) { return found }
        }
        return nil
    }
}
