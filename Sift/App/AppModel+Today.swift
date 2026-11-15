import Foundation

enum TodayStore {
    /// The saved source that holds what the user kept from Today.
    static let keptSourceID = "kept"
}

/// Today (Engine/Today.swift): the digest of offered items, and keeping.
extension AppModel {
    var isKept: Bool { state.deviceID == TodayStore.keptSourceID }

    var todayPicks: [TodayPick] { state.today?.picks ?? [] }

    /// Picks not seen and not kept: the count beside Today in the sidebar.
    var todayOpenCount: Int {
        let kept = Set(state.kept.map(\.url))
        return todayPicks.filter { !isSeen($0.url) && !kept.contains($0.url) }.count
    }

    func isKept(_ url: String) -> Bool { state.kept.contains { $0.url == url } }

    /// Kept items as links of the saved source "Kept from Today". Their feed
    /// text and image fill the preview until Sift captures the page.
    func keptTabs() -> [SafariTab] {
        state.kept.sorted { $0.kept > $1.kept }.map { k in
            if previews[k.url] == nil, !k.summary.isEmpty || k.image != nil {
                previews[k.url] = Preview(title: k.title, text: k.summary, imageURL: k.image, site: k.feedTitle, fetched: Date())
            }
            return SafariTab(url: k.url, title: k.title, lastViewed: k.kept, source: TodayStore.keptSourceID)
        }
    }

    /// Builds the digest when a new slot (07:00, 17:00) has started, or when
    /// `force` is set. Runs after a feed check and with the library jobs.
    func refreshToday(force: Bool = false) {
        guard !state.feeds.isEmpty else {
            if state.today != nil { state.today = nil }
            return
        }
        let slot = TodayBuilder.currentSlot()
        if !force, let digest = state.today, digest.slot >= slot, !digest.picks.isEmpty { return }
        var entries: [String: [FeedEntry]] = [:]
        for feed in state.feeds where feed.enabled { entries[feed.id] = FeedStore.entries(feed.id) }
        let input = TodayBuilder.Input(
            feeds: state.feeds, entries: entries,
            themes: themes.map { ($0.name, $0.summary) },
            kept: state.kept, isSeen: { [seenMarks] in seenMarks[$0]?.seen ?? false })
        state.today = TodayDigest(slot: slot, built: Date(), picks: TodayBuilder.build(input))
        writeTodayForPhone()
    }

    // MARK: The phone (prototypes/ios-deck): iCloud Drive/Sift

    /// Today for the phone: iCloud Drive/Sift/Deck/today.json, written each
    /// time the digest or the kept list changes.
    func writeTodayForPhone() {
        guard !Demo.isOn, CloseList.iCloudDriveAvailable, let digest = state.today else { return }
        struct File: Encodable {
            var schema = 1
            var slot: Date
            var next: Date
            var built: Date
            var picks: [TodayPick]
            var kept: [String]
        }
        let file = File(slot: digest.slot, next: TodayBuilder.nextSlot(), built: digest.built,
                        picks: digest.picks, kept: state.kept.map(\.url))
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(file) else { return }
        let dir = CloseList.folder.appending(path: "Deck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "today.json")
        if (try? Data(contentsOf: url)) == data { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Items kept on other devices: iCloud Drive/Sift/kept/<device>.json,
    /// one file per device (the same pattern as seen marks). New ones join
    /// `state.kept` and count as seen.
    func mergeDeviceKept() {
        guard !Demo.isOn else { return }
        let dir = CloseList.folder.appending(path: "kept", directoryHint: .isDirectory)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        var have = Set(state.kept.map(\.url))
        var added: [KeptItem] = []
        for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let items = try? d.decode([KeptItem].self, from: data) else { continue }
            for item in items where have.insert(item.url).inserted { added.append(item) }
        }
        guard !added.isEmpty else { return }
        state.kept += added
        setSeen(added.map(\.url), true)
        writeTodayForPhone()
        reload()
    }

    /// Keeps an offered item: it becomes saved, in "Kept from Today", and
    /// goes through capture, themes and search like any saved link.
    func keep(_ pick: TodayPick) {
        guard !isKept(pick.url) else { return }
        state.kept.append(KeptItem(url: pick.url, title: pick.title, date: pick.date, kept: Date(),
                                   feedID: pick.feedID, feedTitle: pick.feedTitle, summary: pick.summary, image: pick.image))
        setSeen([pick.url], true)
        writeTodayForPhone()
        reload()
    }

    /// 0.7.0 treated feed items as saved links, so some reached the archive.
    /// They are offered, not saved: drop the ones the user never kept, sent
    /// or wrote a note on. Runs once (`state.today` is nil until then).
    func pruneOfferedFromArchive() {
        let kept = Set(state.kept.map(\.url))
        let drop = archive.values.filter {
            $0.source == "feeds" && !kept.contains($0.url) && ($0.takeaway ?? "").isEmpty && state.sent[$0.url] == nil
        }.map(\.url)
        guard !drop.isEmpty else { return }
        for url in drop { archive[url] = nil }
        ArchiveStore.save(archive)
    }

    func unkeep(_ url: String) {
        state.kept.removeAll { $0.url == url }
        writeTodayForPhone()
        reload()
    }
}
