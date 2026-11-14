import Foundation

/// One open Safari tab, as iCloud Tabs syncs it to this Mac.
struct SafariTab: Identifiable, Hashable, Sendable {
    /// The URL is the identity: the same link open twice is one tab here.
    var id: String { url }
    let url: String
    let title: String
    let lastViewed: Date?

    var host: String {
        let h = URL(string: url)?.host() ?? url
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// X and similar sites often sync a bare title such as "x.com".
    var hasUsefulTitle: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t != "X" && t != host && t != "x.com"
    }

    var displayTitle: String { hasUsefulTitle ? title : url }
}

/// A device that syncs tabs through iCloud.
struct SyncedDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tabCount: Int
}

/// A place a tab can go. Most come from git repos under the projects folder;
/// the user can add projects that have no repo.
struct Project: Identifiable, Hashable, Codable, Sendable {
    var id: String { name }
    var name: String
    var summary: String
    var isRepo: Bool

    /// Buckets that are not projects. The sorter may use them too.
    static let personal = "personal"
    static let drop = "drop"
    static let unknown = "unknown"
    static let buckets = [personal, drop, unknown]
}

/// Where a tab was sorted, and why it may matter there.
struct Assignment: Codable, Hashable, Sendable {
    var project: String
    var use: String
    /// True when the user moved the tab by hand. The sorter never overwrites it.
    var manual: Bool
}
