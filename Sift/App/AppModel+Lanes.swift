import Foundation

/// Custom lanes (Engine/Lanes.swift): saving, editing and listing them.
extension AppModel {
    func laneItems(_ lane: Lane) -> [TodayPick] {
        let feeds = Dictionary(offeredFeeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let themeWords = themes.map { ($0.name, TodayBuilder.words($0.name + " " + $0.summary)) }
        return Lanes.items(lane, picks: items(of: offeredFeeds, limit: 3000), feeds: feeds,
                           mode: { self.mode(of: $0, feeds: feeds) },
                           theme: { p in
                               if let m = self.themeByMeaning(p.url) { return m.name }
                               let w = TodayBuilder.words(p.title + " " + p.summary)
                               let best = themeWords.map { ($0.0, $0.1.intersection(w).count) }.max { $0.1 < $1.1 }
                               return best.flatMap { $0.1 >= 3 ? $0.0 : nil }
                           },
                           isSeen: { self.isSeen($0) })
    }

    func saveLane(_ lane: Lane) {
        if let i = state.lanes.firstIndex(where: { $0.id == lane.id }) { state.lanes[i] = lane } else { state.lanes.append(lane) }
        writeLanesForPhone()
    }

    func deleteLane(_ lane: Lane) {
        state.lanes.removeAll { $0.id == lane.id }
        writeLanesForPhone()
    }

    /// iCloud Drive/Sift/Deck/lanes.json: each lane with its items, for the phone.
    func writeLanesForPhone() {
        guard !Demo.isOn, CloseList.iCloudDriveAvailable else { return }
        struct Row: Encodable { var lane: Lane; var rule: String; var picks: [TodayPick] }
        struct File: Encodable { var schema = 1; var built: Date; var lanes: [Row] }
        let rows = state.lanes.map { Row(lane: $0, rule: $0.rule, picks: laneItems($0).prefix(30).map { p in
            var q = p
            q.content = nil
            return q
        }) }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(File(built: Date(), lanes: rows)) else { return }
        let dir = CloseList.folder.appending(path: "Deck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "lanes.json"), options: .atomic)
    }
}
