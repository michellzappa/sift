import AppKit
import Foundation

extension AppModel {
    func selectDevice(_ id: String) {
        state.deviceID = id
        reload()
    }

    /// True when the source is Safari's Reading List, not a device's open tabs.
    var isReadingList: Bool { state.deviceID == ReadingListReader.sourceID }

    static let allSourcesID = "all-sources"
    /// Phone tabs, Reading List, Instagram Saved and X Bookmarks together.
    var isAll: Bool { state.deviceID == Self.allSourcesID }

    /// Sources that are lists, not open tabs: nothing to close on a phone.
    var isSavedList: Bool { isReadingList || isInstagram || isTikTok || isXBookmarks || isKept || currentImport != nil }

    /// A source's name for titles: "Safari · MZ Air", "Instagram Saved".
    func sourceTitle(_ id: String) -> String {
        if let d = devices.first(where: { $0.id == id }) { return "Safari · \(d.name)" }
        if let p = chromeProfiles.first(where: { $0.id == id }) { return [p.browser, chromeProfileName(p)].compactMap { $0 }.joined(separator: " · ") }
        if id == ReadingListReader.sourceID { return "Reading List" }
        if id == InstagramReader.sourceID { return "Instagram Saved" }
        if id == TikTokReader.sourceID { return "TikTok" }
        if id == AppModel.xBookmarksSourceID { return "X Bookmarks" }
        if id == TodayStore.keptSourceID { return "Kept from Today" }
        if let i = state.importedSources.first(where: { LinkImporter.sourcePrefix + $0.id == id }) { return i.name }
        return "Links"
    }

    // MARK: Sites and actions

    /// Sites with at least three tabs, biggest first. The rest count as "other".
    var sites: [(host: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tab in tabs { counts[tab.host, default: 0] += 1 }
        return counts.filter { $0.value >= 3 }.map { ($0.key, $0.value) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    func tabs(onSite host: String) -> [SafariTab] { tabs.filter { $0.host == host } }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
