import Foundation

enum TodayStore {
    /// The saved source that holds what the user kept from Today.
    static let keptSourceID = "kept"
    /// Items kept on other devices: iCloud Drive/Sift/kept/<device>.json.
    static var deviceFolder: URL { CloseList.folder.appending(path: "kept", directoryHint: .isDirectory) }
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
    /// Today updates as feeds bring new items: picks already in Today keep
    /// their place (seen ones too, until they age out of the window) and new
    /// picks go on top, ranked. `force` builds it again from nothing.
    func refreshToday(force: Bool = false) {
        guard !state.feeds.isEmpty else {
            if state.today != nil { state.today = nil }
            return
        }
        var entries: [String: [FeedEntry]] = [:]
        let feedsByID = Dictionary(state.feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let modeOf: (TodayPick) -> ReadingMode = { [unowned self] in self.mode(of: $0, feeds: feedsByID) }
        for feed in offeredFeeds where feed.enabled { entries[feed.id] = FeedStore.entries(feed.id) }
        let events = FeedSignals.loadAll()
        let input = TodayBuilder.Input(
            feeds: offeredFeeds, entries: entries,
            themes: themes.map { ($0.name, $0.summary) },
            kept: state.kept, isSeen: { [seenMarks] in seenMarks[$0]?.seen ?? false },
            affinity: FeedSignals.affinity(events), evidence: FeedSignals.evidence(events), mode: modeOf,
            creators: creatorOfFeed.mapValues { ($0.name, $0.count) },
            themeByMeaning: { [weak self] in self?.themeByMeaning($0) },
            personOf: personOfFeed,
            dials: themeDials)
        let fresh = TodayBuilder.build(input)
        // Old digests (URL titles, "New from") are dropped, not merged.
        let stale = state.today?.picks.contains { $0.title.hasPrefix("http") || $0.reason.hasPrefix("New from ") } ?? false
        let old = (force || stale) ? [] : TodayBuilder.stillCurrent(state.today?.picks ?? [], feeds: state.feeds)
        let merged = TodayBuilder.merge(old: old, fresh: fresh, mode: modeOf)
        guard force || merged.map(\.url) != (state.today?.picks ?? []).map(\.url) else { return }
        state.today = TodayDigest(slot: Date(), built: Date(), picks: merged)
        writeTodayForPhone()
        Task { await fillTodayText() }
    }

    /// The full text of an offered item: the feed's own, else the article
    /// fetched once and kept in the feed's file. Today's copy updates too.
    func fullText(for pick: TodayPick) async -> String? {
        if let c = pick.content, !c.isEmpty { return c }
        if let c = FeedStore.entries(pick.feedID).first(where: { $0.url == pick.url })?.content { return c }
        // A saved link on a trail: the text Sift captured.
        if pick.feedID == Trail.savedFeedID, let t = Library.text(for: pick.url), !t.isEmpty { return t }
        // Not for videos, and not for social posts: their summary is the
        // whole post, and bsky.app and x.com pages are an app, not an article.
        guard pick.url.range(of: #"youtube\.com|youtu\.be|bsky\.app|/@[^/]+/\d+$"#, options: .regularExpression) == nil,
              XClient.statusID(pick.url) == nil,
              pick.summary.count >= 280 || pick.summary.isEmpty || pick.summary.hasSuffix("…"),
              let text = await ArticleText.fetch(pick.url) else { return nil }
        FeedStore.setContent(text, url: pick.url, feedID: pick.feedID)
        if let i = state.today?.picks.firstIndex(where: { $0.url == pick.url }) { state.today?.picks[i].content = text }
        return text
    }

    /// Records what the user did with an offered item, for the ranking.
    func signal(_ pick: TodayPick, _ kind: String, seconds: Double? = nil) {
        FeedSignals.record(SignalEvent(id: UUID().uuidString, feedID: pick.feedID, url: pick.url, kind: kind, seconds: seconds, at: Date()))
    }

    /// A feed's priority, and whether it is the user's choice or Auto.
    func priority(of feed: Feed) -> (value: FeedPriority, auto: Bool) {
        let rate = TodayBuilder.postsPerDay(FeedStore.entries(feed.id))
        return (TodayBuilder.priority(feed, postsPerDay: rate), feed.priority == nil)
    }

    /// What Today knows about each feed, for "How Today Works" and the feed
    /// list header: the same numbers `TodayBuilder.build` uses.
    func standings(_ feeds: [Feed]? = nil) -> [FeedStanding] {
        let events = FeedSignals.loadAll()
        let affinity = FeedSignals.affinity(events)
        let evidence = FeedSignals.evidence(events)
        let keeps = Dictionary(grouping: state.kept.compactMap(\.feedID), by: { $0 }).mapValues(\.count)
        return (feeds ?? state.feeds).map { feed in
            let rate = TodayBuilder.postsPerDay(FeedStore.entries(feed.id))
            return FeedStanding(feed: feed, priority: TodayBuilder.priority(feed, postsPerDay: rate), auto: feed.priority == nil,
                                postsPerDay: rate, affinity: affinity[feed.id] ?? 0, signals: evidence[feed.id] ?? 0,
                                keeps: keeps[feed.id] ?? 0)
        }
    }

    /// Sets a feed's priority; nil returns it to Auto. Today is built again.
    func setPriority(_ feed: Feed, _ value: FeedPriority?) {
        guard let i = state.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        state.feeds[i].priority = value?.rawValue
        refreshToday(force: true)
    }

    /// YouTube Shorts among today's picks, for the phone's vertical cards:
    /// youtube.com/shorts/<id> answers 200 for a Short and redirects for a
    /// normal video. One request each, paced, redirects not followed.
    func markShorts() async {
        guard !Demo.isOn, let picks = state.today?.picks else { return }
        var changed = false
        for pick in picks where pick.vertical == nil {
            guard let r = pick.url.range(of: #"(?:v=|youtu\.be/|/shorts/)([\w-]{11})"#, options: .regularExpression) else { continue }
            let id = String(pick.url[r].suffix(11))
            let short = pick.url.contains("/shorts/") ? true : await ShortsCheck.isShort(id)
            if let i = state.today?.picks.firstIndex(where: { $0.url == pick.url }) {
                state.today?.picks[i].vertical = short
                changed = true
            }
        }
        if changed { writeTodayForPhone() }
    }

    /// After a feed check: today's picks take the newest text and title of
    /// their items (a feed fixed a post, or Sift parses it better now).
    func refreshTodayText() {
        guard var picks = state.today?.picks else { return }
        var changed = false
        var cache: [String: [FeedEntry]] = [:]
        for i in picks.indices {
            let id = picks[i].feedID
            if cache[id] == nil { cache[id] = FeedStore.entries(id) }
            guard let e = cache[id]?.first(where: { $0.url == picks[i].url }) else { continue }
            if let c = e.content, c != picks[i].content { picks[i].content = c; changed = true }
        }
        guard changed else { return }
        state.today?.picks = picks
        writeTodayForPhone()
    }

    /// After a digest: fetch the full text of picks that have only a summary,
    /// one at a time, so the reader (and the phone) has the article.
    func fillTodayText() async {
        guard !Demo.isOn, let picks = state.today?.picks else { return }
        var changed = false
        for pick in picks where (pick.content ?? "").isEmpty {
            if await fullText(for: pick) != nil { changed = true }
        }
        if changed { writeTodayForPhone() }
        await markShorts()
        await fillDiscussions()
    }

    /// The comments Sift holds for a link (Today's picks are the one store,
    /// so the Mac's rows and the phone's today.json show the same).
    func discussion(for url: String) -> Discussion? {
        state.today?.picks.first { $0.url == url }?.discussion
    }

    /// Top comments for Hacker News and Reddit picks (Feeds/Discussion.swift).
    /// Fetched once; fetched again once after 3 hours while the post is
    /// young and had fewer comments than Sift shows, so a new post gets
    /// its comments later. At most 15 posts a round.
    func fillDiscussions() async {
        guard !Demo.isOn, let picks = state.today?.picks else { return }
        let feeds = Dictionary(state.feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var done = 0
        for pick in picks where done < 15 {
            let provider = feeds[pick.feedID].flatMap { $0.provider ?? AppModel.providerID(forFeed: $0.url) }
            guard Discussions.applies(url: pick.url, provider: provider) else { continue }
            if let d = pick.discussion {
                let young = (pick.date ?? .distantPast) > Date().addingTimeInterval(-2 * 86_400)
                guard young, d.comments.count < Discussions.perPost, d.fetched < Date().addingTimeInterval(-3 * 3600) else { continue }
            }
            done += 1
            guard let found = await Discussions.fetch(url: pick.url, provider: provider),
                  let i = state.today?.picks.firstIndex(where: { $0.url == pick.url }) else { continue }
            state.today?.picks[i].discussion = found
            writeTodayForPhone()
        }
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
                        picks: withModes(digest.picks), kept: state.kept.map(\.url))
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(file) else { return }
        let dir = CloseList.folder.appending(path: "Deck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "today.json")
        writeFeedsForPhone()
        if (try? Data(contentsOf: url)) == data { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Items kept on other devices: iCloud Drive/Sift/kept/<device>.json,
    /// one file per device (the same pattern as seen marks). New ones join
    /// `state.kept` and count as seen.
    func mergeDeviceKept() {
        guard !Demo.isOn else { return }
        let dir = TodayStore.deviceFolder
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
        signal(pick, "keep")
        extendTrial(feedID: pick.feedID)
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

/// Asks YouTube whether a video is a Short without following the redirect.
enum ShortsCheck {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    static func isShort(_ id: String) async -> Bool {
        guard await HostGate.shared.admit("youtube.com"), let url = URL(string: "https://www.youtube.com/shorts/\(id)") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "HEAD"
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("SOCS=CAI; CONSENT=YES+cb", forHTTPHeaderField: "Cookie")
        req.httpShouldHandleCookies = false
        guard let (_, response) = try? await URLSession.shared.data(for: req, delegate: NoRedirect()) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

