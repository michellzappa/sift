import Foundation

/// The directory in Follow (Feeds/Directory.swift): built once a week from
/// who the people you follow vouch for.
extension AppModel {
    /// Vouchers sent out at most per round: the feeds you use most first.
    static let directoryVouchers = 80

    var directoryShown: [DirectoryEntry] {
        let dismissed = Set(directory.dismissed)
        let followed = Set(state.feeds.compactMap { Directory.host($0.site ?? $0.url) })
        return directory.entries.filter { !dismissed.contains($0.id) && !followed.contains($0.id) }
    }

    func refreshDirectory(force: Bool = false) {
        guard !Demo.isOn, !isBuildingDirectory else { return }
        if !force, let built = directory.built, Date().timeIntervalSince(built) < Directory.rebuildDays * 86_400 { return }
        let affinity = FeedSignals.affinity(signalEvents())
        var vouchers: [Directory.Voucher] = []
        for f in offeredFeeds where f.enabled && f.trial == nil {
            let place = People.profile(of: f)
            var v = Directory.Voucher(name: f.title, weight: max(0, min(1, affinity[f.id] ?? 0)), site: nil, feedURL: f.url)
            switch place?.platform {
            case "site", "substack": v.site = place?.url
            case "bluesky": v.bluesky = place.map { String($0.handle.dropFirst()) }
            case "mastodon":
                let parts = (place?.handle ?? "").dropFirst().split(separator: "@").map(String.init)
                if parts.count == 2 { v.mastodon = (parts[0], parts[1]) }
            default: continue
            }
            vouchers.append(v)
        }
        vouchers.sort { $0.weight > $1.weight }
        var skip = Set(directory.dismissed)
        for f in state.feeds { if let h = Directory.host(f.site ?? f.url) { skip.insert(h) } }
        var saved: [String: Int] = [:]
        for l in savedLinks() { if let h = Directory.host(l.url), !Directory.isPlatform(h) { saved[h, default: 0] += 1 } }
        var linked: [String: Set<String>] = [:]
        let since = Date().addingTimeInterval(-60 * 86_400)
        for f in offeredFeeds where f.enabled {
            let own = Directory.host(f.site ?? f.url)
            for e in FeedStore.entries(f.id) where (e.date ?? .distantPast) >= since {
                for k in TodayBuilder.outLinks(e) {
                    guard let h = Directory.host(k), h != own, !Directory.isPlatform(h) else { continue }
                    linked[h, default: []].insert(f.title)
                }
            }
        }
        // Theme searches send theme names out: only when the user turned them on.
        let queries = state.directoryThemeSearch
            ? themes.map { t in (t.name, tabs(in: t.name).count) }.sorted { $0.1 > $1.1 }.prefix(6).map(\.0) : []
        for f in state.feeds { if let p = People.profile(of: f), p.platform == "bluesky" { skip.insert("bluesky:" + p.handle.lowercased()) } }
        let inputs = Directory.Inputs(vouchers: Array(vouchers.prefix(Self.directoryVouchers)), skip: skip, savedHosts: saved,
                                      linkedHosts: linked, themeQueries: queries)
        let space = embedSpace
        isBuildingDirectory = true
        Task { [weak self] in
            let entries = await Directory.build(inputs, space: space)
            guard let self else { return }
            self.directory.entries = entries
            self.directory.built = Date()
            Directory.save(self.directory)
            self.isBuildingDirectory = false
            self.writeCreatorsForPhone()
        }
    }

    /// Follows a directory entry and remembers who vouched for it.
    func followDirectory(_ e: DirectoryEntry) {
        guard !Demo.isOn else { exportMessage = Demo.offMessage; return }
        Task {
            guard let found = await FeedProviders.resolve(e.input).first else { note("No feed found for \(e.name)"); return }
            if !state.feeds.contains(where: { $0.url == found.url }) { addFeed(found) }
            if let i = state.feeds.firstIndex(where: { $0.url == found.url }) {
                state.feeds[i].vouchedBy = e.via
                state.feeds[i].vouchedAt = Date()
            }
            noteFollowed(e.name)
            refreshFeedCounts()
            refreshToday()
            writeCreatorsForPhone()
        }
    }

    func dismissDirectory(_ e: DirectoryEntry) {
        directory.dismissed.append(e.id)
        Directory.save(directory)
        writeCreatorsForPhone()
    }
}
