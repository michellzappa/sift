import Foundation

/// What the phone does with Today picks, for the Mac's ranking ("watch
/// time"). The phone writes iCloud Drive/Sift/signals/iphone-<id>.json: a
/// JSON array, newest last, at most 2,000 events, dates as ISO 8601.
/// Kinds: dwell (seconds on screen, 1.5 s or more), skip (less than 1.5 s),
/// open (reader or browser), keep, unseen (marked unseen), play (video
/// started). A copy stays in Documents/signals-here.json.
struct Signal: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case dwell, skip, open, keep, unseen, play }

    var id: String
    var feedID: String
    var url: String
    var kind: Kind
    var seconds: Double?
    var at: Date

    private enum CodingKeys: String, CodingKey { case id, feedID, url, kind, seconds, at }

    init(feedID: String, url: String, kind: Kind, seconds: Double? = nil, at: Date = Date()) {
        self.id = UUID().uuidString.lowercased()
        self.feedID = feedID
        self.url = url
        self.kind = kind
        self.seconds = seconds
        self.at = at
    }

    // `seconds` is written as null when there is none, so every event has
    // the same keys.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(feedID, forKey: .feedID)
        try c.encode(url, forKey: .url)
        try c.encode(kind, forKey: .kind)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(at, forKey: .at)
    }
}

extension Store {
    static let signalLimit = 2_000
    /// Less time on screen than this is a skip, more is a dwell.
    static let dwellThreshold: TimeInterval = 1.5

    private static var signalsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "signals-here.json")
    }

    static func loadSignalsHere() -> [Signal] {
        guard let data = try? Data(contentsOf: signalsURL) else { return [] }
        return (try? coder.1.decode([Signal].self, from: data)) ?? []
    }

    /// Records one event for a Today pick and saves after a short pause.
    func signal(_ kind: Signal.Kind, url: String, feedID: String, seconds: Double? = nil) {
        let rounded = seconds.map { ($0 * 10).rounded() / 10 }
        signals.append(Signal(feedID: feedID, url: url, kind: kind, seconds: rounded))
        if signals.count > Self.signalLimit { signals.removeFirst(signals.count - Self.signalLimit) }
        signalTask?.cancel()
        signalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.saveSignals()
        }
    }

    func signal(_ kind: Signal.Kind, _ pick: TodayPick, seconds: Double? = nil) {
        signal(kind, url: pick.url, feedID: pick.feedID, seconds: seconds)
    }

    /// The time a Today pick was on screen: a dwell from 1.5 s, else a skip.
    func signalShown(_ pick: TodayPick, seconds: TimeInterval) {
        if seconds >= Self.dwellThreshold {
            signal(.dwell, pick, seconds: seconds)
        } else {
            signal(.skip, pick, seconds: seconds)
        }
    }

    private func saveSignals() {
        guard let data = try? Self.coder.0.encode(signals) else { return }
        try? data.write(to: Self.signalsURL, options: .atomic)
        withFolder { writeSignals(data, to: $0) }
    }

    /// Writes this phone's signals file into the connected folder.
    func writeSignals(to folder: URL) {
        guard !signals.isEmpty, let data = try? Self.coder.0.encode(signals) else { return }
        writeSignals(data, to: folder)
    }

    private func writeSignals(_ data: Data, to folder: URL) {
        let dir = folder.appending(path: "signals", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: Self.deviceFile), options: .atomic)
    }
}
