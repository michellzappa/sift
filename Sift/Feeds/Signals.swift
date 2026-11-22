import Foundation

// What the user does with offered items, as the ranking's evidence, the way
// short-video apps use watch time. Events from this Mac live in
// Application Support/Sift/signals.json; the phone writes its own to
// iCloud Drive/Sift/signals/iphone-<id>.json (one file per device, like seen
// marks). `FeedSignals.affinity` turns them into a weight per feed.

struct SignalEvent: Codable, Hashable, Sendable {
    var id: String
    var feedID: String
    var url: String
    /// dwell, skip, open, keep, unseen, play
    var kind: String
    var seconds: Double?
    var at: Date
}

/// How a feed takes part in Today. Nil on the feed means Auto: Sift picks
/// Best only for feeds that post more than `busyPerDay` (5: Hacker News
/// lands there, a blog does not), else Normal.
enum FeedPriority: String, Codable, CaseIterable, Sendable {
    case must, normal, best, off

    var label: String {
        switch self {
        case .must: "Don't Miss"
        case .normal: "Normal"
        case .best: "Best Only"
        case .off: "Not in Today"
        }
    }

    static let busyPerDay = 5.0
}

enum FeedSignals {
    static var localURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "signals.json") }
    static var deviceFolder: URL { CloseList.folder.appending(path: "signals", directoryHint: .isDirectory) }
    static let keep = 2_000

    private static var coder: (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    static func loadLocal() -> [SignalEvent] {
        guard let data = try? Data(contentsOf: localURL) else { return [] }
        return (try? coder.1.decode([SignalEvent].self, from: data)) ?? []
    }

    static func record(_ event: SignalEvent) {
        guard !Demo.isOn else { return }
        var all = loadLocal()
        all.append(event)
        if all.count > keep { all.removeFirst(all.count - keep) }
        if let data = try? coder.0.encode(all) { try? data.write(to: localURL, options: .atomic) }
    }

    /// This Mac's events and every device's file in iCloud Drive/Sift/signals.
    static func loadAll() -> [SignalEvent] {
        var all = loadLocal()
        let files = (try? FileManager.default.contentsOfDirectory(at: deviceFolder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let events = try? coder.1.decode([SignalEvent].self, from: data) {
                all += events
            }
        }
        return all
    }

    /// Weight per feed in -1…1 from recent behaviour (half-life about three
    /// weeks): keeps and reading pull it up, quick skips pull it down a little.
    static func affinity(_ events: [SignalEvent], now: Date = Date()) -> [String: Double] {
        var sum: [String: Double] = [:]
        for e in events where !e.feedID.isEmpty {
            let days = max(0, now.timeIntervalSince(e.at) / 86_400)
            let decay = exp(-days / 30)
            sum[e.feedID, default: 0] += weight(e) * decay
        }
        return sum.mapValues { tanh($0 / 5) }
    }

    /// The weight of one signal, shared by feed and network learning.
    static func weight(_ e: SignalEvent) -> Double {
        switch e.kind {
        case "keep": 3
        case "open", "play", "unseen": 1
        case "dwell": min((e.seconds ?? 0) / 10, 2) * 0.5
        case "skip": -0.4
        // Not interested: less from this source.
        case "less": -1.5
        default: 0
        }
    }

    /// What Sift learned per network (Engine/NetworkDial.swift) from the
    /// last `NetworkStats.days` days. `seenPicks` are Today picks you saw
    /// without a signal (scrolled past in Scan): they count as shown.
    /// Learned = tanh(mean weight per item − the mean over all networks),
    /// shrunk by n / (n + 10), so a network needs evidence to move.
    static func networks(_ events: [SignalEvent], networkOf: [String: Network], seenPicks: [(url: String, network: Network)],
                         now: Date = Date()) -> [Network: NetworkStats] {
        let since = now.addingTimeInterval(-NetworkStats.days * 86_400)
        struct Item { var weight = 0.0; var opened = false; var kept = false; var skipped = false }
        var items: [Network: [String: Item]] = [:]
        for e in events where e.at >= since {
            guard let n = networkOf[e.feedID] else { continue }
            let decay = exp(-max(0, now.timeIntervalSince(e.at)) / 86_400 / 30)
            var it = items[n]?[e.url] ?? Item()
            it.weight += weight(e) * decay
            if ["open", "play", "keep"].contains(e.kind) { it.opened = true }
            if e.kind == "keep" { it.kept = true }
            if e.kind == "skip" { it.skipped = true }
            items[n, default: [:]][e.url] = it
        }
        for p in seenPicks where items[p.network]?[p.url] == nil { items[p.network, default: [:]][p.url] = Item() }
        let all = items.values.flatMap(\.values)
        let overall = all.isEmpty ? 0 : all.map(\.weight).reduce(0, +) / Double(all.count)
        return items.mapValues { byURL in
            let list = Array(byURL.values)
            let n = list.count
            let mean = list.map(\.weight).reduce(0, +) / Double(max(n, 1))
            let learned = n < NetworkStats.minShown ? 0 : tanh(mean - overall) * Double(n) / Double(n + 10)
            return NetworkStats(shown: n, opened: list.filter(\.opened).count, kept: list.filter(\.kept).count,
                                skipped: list.filter(\.skipped).count, learned: learned)
        }
    }

    /// How many signals a feed has: few means Sift knows little about it yet.
    static func evidence(_ events: [SignalEvent]) -> [String: Int] {
        Dictionary(grouping: events.filter { !$0.feedID.isEmpty }, by: \.feedID).mapValues(\.count)
    }
}
