import Foundation

extension AppModel {
    // MARK: Scan, Watch, Read (Engine/Modes.swift)

    /// The feed's own setting, else nil (Auto).
    func mode(of feed: Feed) -> ReadingMode? { feed.mode.flatMap(ReadingMode.init(rawValue:)) }

    func setMode(_ feed: Feed, _ mode: ReadingMode?) {
        guard let i = state.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        state.feeds[i].mode = mode?.rawValue
        writeTodayForPhone()
    }

    /// What Auto picks for a feed: from its provider, else from most of its items.
    func autoMode(of feed: Feed) -> ReadingMode {
        if let set = Modes.providerMode(feed.provider ?? AppModel.providerID(forFeed: feed.url)) { return set }
        let entries = FeedStore.entries(feed.id).prefix(30)
        guard !entries.isEmpty else { return .scan }
        var counts: [ReadingMode: Int] = [:]
        for e in entries { counts[Modes.mode(url: e.url, words: Modes.words(e.content ?? e.summary)), default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? .scan
    }

    func mode(of pick: TodayPick, feeds: [String: Feed]) -> ReadingMode {
        let feed = feeds[pick.feedID]
        if let feed, let set = mode(of: feed) { return set }
        if pick.vertical == true { return .watch }
        let byProvider = feed.flatMap { Modes.providerMode($0.provider ?? AppModel.providerID(forFeed: $0.url)) }
        return Modes.mode(url: pick.url, words: Modes.words(pick.content), provider: byProvider)
    }

    func mode(of tab: SafariTab) -> ReadingMode {
        let entry = library[tab.url]
        if entry?.transcript == true || entry?.duration != nil { return .watch }
        let words = entry?.status == "ok" ? entry?.words ?? 0 : 0
        return Modes.mode(url: tab.url, words: words)
    }

    /// The picks in the current mode (all of them when the switch is on All).
    func inMode(_ picks: [TodayPick]) -> [TodayPick] {
        guard let listMode else { return picks }
        let feeds = Dictionary(state.feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return picks.filter { mode(of: $0, feeds: feeds) == listMode }
    }

    func inMode(_ tabs: [SafariTab]) -> [SafariTab] {
        guard let listMode else { return tabs }
        return tabs.filter { mode(of: $0) == listMode }
    }

    /// The picks with their mode filled in, for the phone's Scan, Watch and
    /// Read tabs.
    func withModes(_ picks: [TodayPick]) -> [TodayPick] {
        let feeds = Dictionary(state.feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return picks.map { var p = $0; p.mode = mode(of: p, feeds: feeds).rawValue; return p }
    }
}
