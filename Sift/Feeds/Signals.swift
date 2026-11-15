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
            let w: Double
            switch e.kind {
            case "keep": w = 3
            case "open", "play", "unseen": w = 1
            case "dwell": w = min((e.seconds ?? 0) / 10, 2) * 0.5
            case "skip": w = -0.4
            default: w = 0
            }
            sum[e.feedID, default: 0] += w * decay
        }
        return sum.mapValues { tanh($0 / 5) }
    }

    /// How many signals a feed has: few means Sift knows little about it yet.
    static func evidence(_ events: [SignalEvent]) -> [String: Int] {
        Dictionary(grouping: events.filter { !$0.feedID.isEmpty }, by: \.feedID).mapValues(\.count)
    }
}
