import Foundation

// Feeds shared with the phone (owner, 2026-11-15: "feeds be shared between
// mac/ios"). The Mac is the one that fetches feeds; the phone sees the same
// list and can ask for changes.
//
// - The Mac writes iCloud Drive/Sift/Deck/feeds.json: every followed feed
//   (no items) and the outcome of each phone request.
// - The phone writes iCloud Drive/Sift/follows/iphone-<id>.json: a list of
//   requests (follow by anything the Follow sheet takes, unfollow, priority,
//   folder). One file per device, like seen/ and kept/, so iCloud never sees
//   a write conflict.
// - The Mac handles each request id once (`state.phoneRequests`).

/// One request from the phone.
struct PhoneFeedRequest: Codable, Sendable, Hashable {
    var id: String
    /// "follow", "unfollow", "priority" or "folder".
    var kind: String
    /// For follow: what the user typed (a site, r/swift, @name.bsky.social).
    var input: String?
    /// For the others: the feed id.
    var feedID: String?
    var folder: String?
    /// `FeedPriority` raw value, or nil for Auto.
    var priority: String?
    /// Your Graph: the `Creator.id` a follow comes from, or the creator to
    /// hide or show (kinds "hide", "show").
    var creator: String? = nil
    var at: Date
}

extension AppModel {
    func writeFeedsForPhone() {
        guard !Demo.isOn, CloseList.iCloudDriveAvailable else { return }
        struct Row: Encodable {
            var id, title, url: String
            var site, folder, provider, priority: String?
            var enabled: Bool
            var items: Int
        }
        struct File: Encodable {
            var schema = 1
            var feeds: [Row]
            var requests: [String: String]
        }
        let rows = state.feeds.filter { $0.trial == nil }.map {
            Row(id: $0.id, title: $0.title, url: $0.url, site: $0.site, folder: $0.category, provider: $0.provider,
                priority: $0.priority, enabled: $0.enabled, items: feedItemCounts[$0.id] ?? 0)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(File(feeds: rows, requests: state.phoneRequests)) else { return }
        let dir = CloseList.folder.appending(path: "Deck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "feeds.json")
        if (try? Data(contentsOf: url)) == data { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Reads every device's follows/ file and acts on requests not handled yet.
    func mergeDeviceFollows() {
        guard !Demo.isOn else { return }
        let dir = CloseList.folder.appending(path: "follows", directoryHint: .isDirectory)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        var pending: [PhoneFeedRequest] = []
        for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let list = try? d.decode([PhoneFeedRequest].self, from: data) else { continue }
            pending += list.filter { state.phoneRequests[$0.id] == nil }
        }
        guard !pending.isEmpty else { return }
        for r in pending.sorted(by: { $0.at < $1.at }) {
            switch r.kind {
            case "follow":
                // X, Instagram and TikTok authors have no feed: never fetch their pages.
                guard let input = r.input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty,
                      Creators.hasFeed(r.creator ?? "") else {
                    state.phoneRequests[r.id] = "failed"; continue
                }
                state.phoneRequests[r.id] = "working"
                Task {
                    let found = await FeedProviders.resolve(input).first
                    if let found {
                        if !state.feeds.contains(where: { $0.url == found.url }) {
                            addFeed(found, category: r.folder, priority: r.priority.flatMap(FeedPriority.init(rawValue:)))
                            noteFollowed(found.label ?? found.parsed.title)
                        }
                        if let creator = r.creator, creator.hasPrefix("directory:"),
                           let entry = directory.entries.first(where: { $0.id == String(creator.dropFirst(10)) }),
                           let i = state.feeds.firstIndex(where: { $0.url == found.url }) {
                            // Followed from the phone's directory: remember who vouched.
                            state.feeds[i].vouchedBy = entry.via
                            state.feeds[i].vouchedAt = Date()
                            writeCreatorsForPhone()
                        } else if let creator = r.creator, creator.hasPrefix("place:") {
                            // "place:<Place.id>": a person's place, followed from the phone.
                            if let i = state.feeds.firstIndex(where: { $0.url == found.url }) { state.feeds[i].place = String(creator.dropFirst(6)) }
                            writeCreatorsForPhone()
                        } else if let creator = r.creator, creator.hasPrefix("farther:") {
                            // "farther:<theme>:<input>": take it off that theme's list.
                            let parts = creator.split(separator: ":", maxSplits: 2).map(String.init)
                            if parts.count == 3 {
                                farther[parts[1]]?.suggestions.removeAll { $0.id == parts[2] }
                                Farther.save(farther)
                                writeCreatorsForPhone()
                            }
                        } else if let creator = r.creator, let i = state.feeds.firstIndex(where: { $0.url == found.url }) {
                            state.feeds[i].creator = creator
                            refreshCreators()
                        }
                        state.phoneRequests[r.id] = "followed"
                    } else {
                        state.phoneRequests[r.id] = "failed"
                    }
                    writeFeedsForPhone()
                }
            case "triage":
                // Scan's Saved part on the phone: keep, letGo or send one saved link.
                if let url = r.input, let tab = tabs.first(where: { $0.url == url }) ?? archive[url]?.asTab {
                    switch r.priority {
                    case "letGo":
                        move(tab, to: Project.drop)
                    case "send":
                        if let d = defaultDestination(for: tab) { Task { await send(tab, to: d) } }
                        else { note("\(tab.title) has no destination: its theme sends nowhere") }
                    default:
                        break
                    }
                    setSeen([url], true)
                }
                state.phoneRequests[r.id] = "done"
            case "less":
                // Not interested from the phone: input = the pick's URL, priority = source, topic or story.
                if let url = r.input, let pick = state.today?.picks.first(where: { $0.url == url }),
                   let reason = LessOf(rawValue: r.priority ?? "") {
                    notInterested(pick, reason)
                }
                state.phoneRequests[r.id] = "done"
            case "dial":
                // A theme dial set on the phone: input = theme, priority = dial.
                if let theme = r.input, let d = ThemeDial(rawValue: r.priority ?? "") { setDial(d, for: theme) }
                state.phoneRequests[r.id] = "done"
            case "trial-follow", "trial-stop":
                if let f = state.feeds.first(where: { $0.id == r.feedID && $0.trial != nil }) {
                    if r.kind == "trial-follow" { followTrial(f) } else { stopTrial(f) }
                }
                state.phoneRequests[r.id] = "done"
            case "dismiss":
                // Not interested in a directory entry (creator = "directory:<id>").
                if let c = r.creator, c.hasPrefix("directory:") {
                    directory.dismissed.append(String(c.dropFirst(10)))
                    Directory.save(directory)
                    writeCreatorsForPhone()
                }
                state.phoneRequests[r.id] = "done"
            case "unfollow":
                if let feed = state.feeds.first(where: { $0.id == r.feedID }) { removeFeed(feed) }
                state.phoneRequests[r.id] = "done"
            case "priority":
                if let feed = state.feeds.first(where: { $0.id == r.feedID }) {
                    setPriority(feed, r.priority.flatMap(FeedPriority.init(rawValue:)))
                }
                state.phoneRequests[r.id] = "done"
            case "folder":
                if let id = r.feedID { moveFeed(id, to: r.folder) }
                state.phoneRequests[r.id] = "done"
            case "farther":
                if let theme = r.input, let project = themes.first(where: { $0.name == theme }) {
                    Task { await askFarther(project) }
                }
                state.phoneRequests[r.id] = "done"
            case "hide", "show":
                if let id = r.creator {
                    state.hiddenCreators.removeAll { $0 == id }
                    if r.kind == "hide" { state.hiddenCreators.append(id) }
                    writeCreatorsForPhone()
                }
                state.phoneRequests[r.id] = "done"
            default:
                state.phoneRequests[r.id] = "failed"
            }
        }
        writeFeedsForPhone()
    }
}

extension AppModel {
    /// Your Graph for the phone: iCloud Drive/Sift/Deck/creators.json. The
    /// phone shows it and asks for follows and hides through follows/.
    func writeCreatorsForPhone() {
        guard !Demo.isOn, CloseList.iCloudDriveAvailable else { return }
        struct Save: Encodable { var url, title: String; var date: Date; var theme: String? }
        struct Row: Encodable {
            var id, kind, name, input: String
            var count, recent: Int
            var score, bonus: Double
            var lastSaved: Date?
            var themes: [String: Int]
            var feedID: String?
            var hidden: Bool
            var saves: [Save]
            var rank: Double?
            var closeTo: [String]?
            /// False for X, Instagram and TikTok authors (no Follow).
            var hasFeed: Bool
        }
        struct Evidence: Encodable { var from, item, itemURL, link: String }
        struct Near: Encodable {
            var id, kind, name, input: String
            var linkedBy: [String]
            var mentions: Int
            var score: Double
            var themes: [String: Int]
            var evidence: [Evidence]
        }
        struct File: Encodable {
            var schema = 1
            var halfLifeDays = Creators.halfLifeDays
            var minSaves = Creators.minSaves
            var creators: [Row]
            var nextDoor: [Near]
            var farther: [String: FartherResult]
            var fartherAsking: [String]
            var people: [PersonRow]
            var themeTerms: [String: [String]]
            var directory: [DirectoryEntry]
            var directoryBuilt: Date?
            var dials: [String: String]
            var trials: [TrialRow]
            var subClusters: [String: [SubClusterRow]]
        }
        struct SubClusterRow: Encodable { var name: String; var count: Int }
        struct TrialRow: Encodable { var feedID, title, url, theme: String; var source: String?; var until: Date? }
        struct PlaceRow: Encodable { var id, platform, platformName, url, handle: String; var hasFeed, followed: Bool }
        struct PersonRow: Encodable { var id, name: String; var places: [PlaceRow]; var evidence: [String] }
        let hidden = Set(state.hiddenCreators)
        let names = Dictionary(creators.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let rows = creators.map { c in
            Row(id: c.id, kind: c.kind.rawValue, name: c.name, input: c.input, count: c.count, recent: c.recent,
                score: (c.score * 100).rounded() / 100, bonus: (TodayBuilder.creatorBonus(c.count) * 100).rounded() / 100,
                lastSaved: c.lastSaved, themes: Dictionary(c.themes.map { ($0.name, $0.count) }, uniquingKeysWith: { a, _ in a }),
                feedID: c.feedID, hidden: hidden.contains(c.id),
                saves: c.saves.prefix(8).map { Save(url: $0.url, title: $0.title, date: $0.date, theme: $0.theme) },
                rank: creatorRank[c.id].map { ($0 * 100).rounded() / 100 },
                closeTo: creatorSimilar[c.id]?.compactMap { n in names[n.id] }, hasFeed: c.hasFeed)
        }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601
        let near = visibleNeighbors.map { n in
            Near(id: n.id, kind: n.kind.rawValue, name: n.name, input: n.input, linkedBy: n.linkedBy, mentions: n.mentions,
                 score: (n.score * 100).rounded() / 100,
                 themes: Dictionary(n.themes.map { ($0.name, $0.count) }, uniquingKeysWith: { a, _ in a }),
                 evidence: n.evidence.prefix(6).map { Evidence(from: $0.from, item: $0.item, itemURL: $0.itemURL, link: $0.link) })
        }
        let peopleRows = people.map { person in
            PersonRow(id: person.id, name: person.name, places: person.profiles.map { p in
                PlaceRow(id: p.id, platform: p.platform, platformName: p.platformName, url: p.url, handle: p.handle,
                         hasFeed: p.hasFeed, followed: followedFeed(for: p) != nil)
            }, evidence: person.evidence)
        }
        guard let data = try? e.encode(File(creators: rows, nextDoor: near, farther: farther, fartherAsking: fartherAsking.sorted(),
                                            people: peopleRows, themeTerms: themeTerms, directory: directoryShown, directoryBuilt: directory.built,
                                            dials: themeDials.filter { $0.value != .stay }.mapValues(\.rawValue),
                                            trials: trialFeeds.map { TrialRow(feedID: $0.id, title: $0.title, url: $0.url, theme: $0.trial ?? "",
                                                                              source: $0.trialSource, until: $0.trialUntil) },
                                            subClusters: subClusters.mapValues { $0.map { SubClusterRow(name: $0.name, count: $0.size) } })) else { return }
        let dir = CloseList.folder.appending(path: "Deck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "creators.json")
        if (try? Data(contentsOf: url)) == data { return }
        try? data.write(to: url, options: .atomic)
    }
}
