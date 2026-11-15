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
        let rows = state.feeds.map {
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
                guard let input = r.input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
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
                        state.phoneRequests[r.id] = "followed"
                    } else {
                        state.phoneRequests[r.id] = "failed"
                    }
                    writeFeedsForPhone()
                }
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
            default:
                state.phoneRequests[r.id] = "failed"
            }
        }
        writeFeedsForPhone()
    }
}
