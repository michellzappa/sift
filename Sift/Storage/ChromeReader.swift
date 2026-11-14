import Foundation

/// Reads the open tabs that Sift's Chrome extension reports, one snapshot
/// file per browser profile. The extension sends them through the
/// `sift-chrome` native messaging host, which writes
/// ~/Library/Application Support/Sift/chrome/tabs-<install>.json.
/// Each profile is a source, "chrome:<install>". Sift writes only
/// close.json in that folder: the URLs to close in Chrome.
enum ChromeReader {
    static let sourcePrefix = "chrome:"
    /// A snapshot older than this shows as stale.
    static let staleAfter: TimeInterval = 24 * 3600

    static var folder: URL {
        StateFile.url.deletingLastPathComponent().appending(path: "chrome", directoryHint: .isDirectory)
    }

    static var closeFile: URL { folder.appending(path: "close.json") }

    /// The file sift-chrome writes (SiftChrome/main.swift, `Snapshot`).
    struct Snapshot: Decodable {
        struct Tab: Decodable {
            let url: String
            let title: String
            let lastAccessed: Double?
        }
        let install: String
        let browser: String
        let updated: Date
        let tabs: [Tab]
    }

    struct Profile: Identifiable, Hashable, Sendable {
        /// The source id: "chrome:<install>".
        var id: String { ChromeReader.sourcePrefix + install }
        let install: String
        /// The browser as the user knows it: "Chrome", "Brave", "Edge".
        let browser: String
        let updated: Date
        /// One per URL, most recently used first.
        let tabs: [SafariTab]

        var isStale: Bool { Date().timeIntervalSince(updated) > ChromeReader.staleAfter }
    }

    static func profiles() -> [Profile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.lastPathComponent.hasPrefix("tabs-") && $0.pathExtension == "json" }
            .compactMap { file -> Profile? in
                guard let data = try? Data(contentsOf: file),
                      let s = try? decoder.decode(Snapshot.self, from: data) else { return nil }
                var newest: [String: (title: String, seen: Date?)] = [:]
                for t in s.tabs {
                    let seen = t.lastAccessed.map { Date(timeIntervalSince1970: $0 / 1000) }
                    if let old = newest[t.url], (old.seen ?? .distantPast) >= (seen ?? .distantPast) { continue }
                    newest[t.url] = (t.title.replacingOccurrences(of: "\n", with: " "), seen)
                }
                let tabs = newest.map { SafariTab(url: $0.key, title: $0.value.title, lastViewed: $0.value.seen) }
                    .sorted { ($0.lastViewed ?? .distantPast) > ($1.lastViewed ?? .distantPast) }
                return Profile(install: s.install, browser: shortName(s.browser), updated: s.updated, tabs: tabs)
            }
            .sorted { $0.browser == $1.browser ? $0.install < $1.install : $0.browser < $1.browser }
    }

    /// "Google Chrome" shows as "Chrome", "Brave Browser" as "Brave".
    static func shortName(_ browser: String) -> String {
        switch browser {
        case "Google Chrome": "Chrome"
        case "Google Chrome Beta": "Chrome Beta"
        case "Google Chrome Dev": "Chrome Dev"
        case "Google Chrome Canary": "Chrome Canary"
        case "Brave Browser", "Brave Browser Beta": "Brave"
        case "Microsoft Edge": "Edge"
        default: browser.isEmpty ? "Chrome" : browser
        }
    }

    /// The newest change to any snapshot, so Sift reloads only when a
    /// profile reported something new.
    static func latestChange() -> Date? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("tabs-") }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    /// Forgets a profile. It comes back when its extension reports again.
    static func remove(_ profile: Profile) {
        try? FileManager.default.removeItem(at: folder.appending(path: "tabs-\(profile.install).json"))
    }

    /// Writes the URLs to close in Chrome. sift-chrome answers each profile
    /// with the ones open there; the extension closes them.
    static func writeClose(_ urls: [String]) {
        let sorted = urls.sorted()
        if let data = try? Data(contentsOf: closeFile),
           let old = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (old["urls"] as? [String]) == sorted { return }
        // Nothing to close and no file yet: leave the folder alone.
        if sorted.isEmpty, !FileManager.default.fileExists(atPath: closeFile.path(percentEncoded: false)) { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: ["urls": sorted], options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        try? data.write(to: closeFile, options: .atomic)
    }
}
