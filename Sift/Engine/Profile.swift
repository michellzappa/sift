import Foundation

/// What Sift knows about the person, beyond the interest graph: where saves
/// come from, when and how they read, what they finish and skip, how themes
/// move, and which files hold it all. Settings > You shows it; Export as
/// JSON writes it as is. `build` is pure: it takes plain inputs
/// (`AppModel+Profile` gathers them) and reads no files, no app state and
/// no network, so the numbers can be checked by hand.
struct Profile: Codable, Sendable {
    struct Count: Codable, Sendable, Hashable, Identifiable {
        var name: String
        var count: Int
        var id: String { name }
    }

    /// One calendar month, "2026-11".
    struct Month: Codable, Sendable, Hashable, Identifiable {
        var month: String
        var count: Int
        var id: String { month }
    }

    struct Clock: Codable, Sendable {
        /// 24 counts, hour 0 to 23, local time.
        var hours: [Int]
        /// 7 counts, Monday first.
        var weekdays: [Int]
        static let empty = Clock(hours: Array(repeating: 0, count: 24), weekdays: Array(repeating: 0, count: 7))
        var total: Int { hours.reduce(0, +) }
    }

    struct FeedHabit: Codable, Sendable, Hashable, Identifiable {
        var feedID: String
        var title: String
        var dwellSeconds: Double
        var opens: Int
        var keeps: Int
        var skips: Int
        var id: String { feedID }
    }

    struct ThemeTrend: Codable, Sendable, Hashable, Identifiable {
        var name: String
        /// Saves per month, same order as `Profile.themeMonths`.
        var months: [Int]
        var total: Int
        /// rising, falling or steady: the last 3 months against the 3 before.
        var trend: String
        var id: String { name }
    }

    struct DataFile: Codable, Sendable, Hashable, Identifiable {
        var name: String
        var path: String
        var bytes: Int64
        var exists: Bool
        var note: String
        var id: String { path }
    }

    var generated: Date

    // At a glance
    var savedLinks: Int
    var sources: Int
    var themes: Int
    var followedFeeds: Int
    var creators: Int
    /// Device files found in iCloud Drive/Sift (seen, kept, signals), plus
    /// this Mac.
    var devices: [String]

    // Where saves come from
    var bySource: [Count]
    /// The last 12 months, oldest first.
    var perMonth: [Month]

    // When you read
    var mac: Clock
    var phone: Clock

    // How you read
    /// Items opened or marked seen, per mode (Scan, Watch, Read).
    var modes: [Count]
    var opened: Int
    var medianReadMinutes: Int?
    var readSample: Int
    var medianVideoSeconds: Int?
    var videoSample: Int
    /// Today picks opened, played or kept, and kept.
    var todayOpened: Int
    var todayKept: Int
    var keepRate: Double?

    // What you finish and skip
    var feeds: [FeedHabit]
    var mostKept: [FeedHabit]
    var mostSkipped: [FeedHabit]

    // Themes over time
    var themeMonths: [String]
    var themeTrends: [ThemeTrend]

    // Files
    var files: [DataFile]

    // MARK: Inputs

    #if os(macOS)

    struct Saved: Sendable {
        var url: String
        /// The source's display name ("Safari tabs", "Reading List").
        var source: String
        var date: Date
        var theme: String?
    }

    /// A seen mark or signal, with the device that made it.
    struct Moment: Sendable {
        /// "mac", "iphone" or another file prefix.
        var device: String
        var at: Date
    }

    struct Inputs: Sendable {
        var saved: [Saved] = []
        var themeNames: [String] = []
        var followedFeeds = 0
        var creators = 0
        var devices: [String] = []
        var feedTitles: [String: String] = [:]
        /// Seen marks with seen == true, URL and device.
        var seen: [(url: String, moment: Moment)] = []
        var signals: [(event: SignalEvent, device: String)] = []
        /// The mode per URL where Sift knows it (library, Today, feeds).
        var modeOf: [String: ReadingMode] = [:]
        /// Words of text per URL, where Sift has the text.
        var wordsOf: [String: Int] = [:]
        /// Video length in seconds per URL (library `duration`).
        var durationOf: [String: Int] = [:]
        var files: [DataFile] = []
        var now = Date()
        var calendar = Calendar.current
    }

    // MARK: Build

    static let topFeeds = 5
    /// A quick skip: the phone's `skip` signal (under 1.5 s on screen).
    static let openKinds: Set<String> = ["open", "play", "keep"]

    static func build(_ input: Inputs) -> Profile {
        let cal = input.calendar
        let now = input.now

        // Where saves come from
        var sourceCounts: [String: Int] = [:]
        for s in input.saved { sourceCounts[s.source, default: 0] += 1 }
        let bySource = sourceCounts.map { Count(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        let months = lastMonths(12, now: now, calendar: cal)
        var monthCounts: [String: Int] = [:]
        for s in input.saved { monthCounts[monthKey(s.date, cal), default: 0] += 1 }
        let perMonth = months.map { Month(month: $0, count: monthCounts[$0] ?? 0) }

        // When you read
        var mac = Clock.empty, phone = Clock.empty
        func add(_ m: Moment) {
            let hour = cal.component(.hour, from: m.at)
            // Calendar weekday: 1 = Sunday. Monday first here.
            let weekday = (cal.component(.weekday, from: m.at) + 5) % 7
            if m.device == "mac" {
                mac.hours[hour] += 1; mac.weekdays[weekday] += 1
            } else {
                phone.hours[hour] += 1; phone.weekdays[weekday] += 1
            }
        }
        for s in input.seen { add(s.moment) }
        for s in input.signals { add(Moment(device: s.device, at: s.event.at)) }

        // How you read
        var opened = Set(input.seen.map(\.url))
        for s in input.signals where openKinds.contains(s.event.kind) { opened.insert(s.event.url) }
        var modeCounts: [ReadingMode: Int] = [:]
        var readMinutes: [Int] = []
        var videoSeconds: [Int] = []
        for url in opened {
            let words = input.wordsOf[url] ?? 0
            let mode = input.modeOf[url] ?? Modes.mode(url: url, words: words)
            modeCounts[mode, default: 0] += 1
            if mode == .read, words > 0 { readMinutes.append(Modes.minutes(words)) }
            if mode == .watch, let d = input.durationOf[url], d > 0 { videoSeconds.append(d) }
        }
        let modes = ReadingMode.allCases.map { Count(name: $0.title, count: modeCounts[$0] ?? 0) }
        let todayOpenedURLs = Set(input.signals.filter { openKinds.contains($0.event.kind) }.map(\.event.url))
        let todayKeptURLs = Set(input.signals.filter { $0.event.kind == "keep" }.map(\.event.url))

        // What you finish and skip
        var habits: [String: FeedHabit] = [:]
        for s in input.signals where !s.event.feedID.isEmpty {
            let id = s.event.feedID
            var h = habits[id] ?? FeedHabit(feedID: id, title: input.feedTitles[id] ?? "Feed no longer followed", dwellSeconds: 0, opens: 0, keeps: 0, skips: 0)
            switch s.event.kind {
            case "dwell": h.dwellSeconds += s.event.seconds ?? 0
            case "open", "play": h.opens += 1
            case "keep": h.keeps += 1
            case "skip": h.skips += 1
            default: break
            }
            habits[id] = h
        }
        func ranked(_ list: [FeedHabit], by value: (FeedHabit) -> Int) -> [FeedHabit] {
            list.sorted { (a: FeedHabit, b: FeedHabit) -> Bool in
                let x = value(a), y = value(b)
                return x == y ? a.title < b.title : x > y
            }
        }
        let all = Array(habits.values)
        let feeds = ranked(all) { $0.opens + $0.keeps }
        let mostKept = Array(ranked(all.filter { $0.keeps > 0 }) { $0.keeps }.prefix(topFeeds))
        let mostSkipped = Array(ranked(all.filter { $0.skips > 0 }) { $0.skips }.prefix(topFeeds))

        // Themes over time
        let themeSet = Set(input.themeNames)
        var perTheme: [String: [String: Int]] = [:]
        for s in input.saved {
            guard let t = s.theme, themeSet.contains(t) else { continue }
            perTheme[t, default: [:]][monthKey(s.date, cal), default: 0] += 1
        }
        var themeTrends: [ThemeTrend] = []
        for name in input.themeNames {
            let byMonth: [String: Int] = perTheme[name] ?? [:]
            var counts: [Int] = []
            for m in months { counts.append(byMonth[m] ?? 0) }
            let total = counts.reduce(0, +)
            guard total > 0 else { continue }
            themeTrends.append(ThemeTrend(name: name, months: counts, total: total, trend: trend(counts)))
        }
        themeTrends.sort { (a: ThemeTrend, b: ThemeTrend) -> Bool in
            a.total == b.total ? a.name < b.name : a.total > b.total
        }

        return Profile(
            generated: now,
            savedLinks: input.saved.count,
            sources: sourceCounts.count,
            themes: input.themeNames.count,
            followedFeeds: input.followedFeeds,
            creators: input.creators,
            devices: input.devices.sorted(),
            bySource: bySource,
            perMonth: perMonth,
            mac: mac,
            phone: phone,
            modes: modes,
            opened: opened.count,
            medianReadMinutes: median(readMinutes),
            readSample: readMinutes.count,
            medianVideoSeconds: median(videoSeconds),
            videoSample: videoSeconds.count,
            todayOpened: todayOpenedURLs.count,
            todayKept: todayKeptURLs.count,
            keepRate: todayOpenedURLs.isEmpty ? nil : Double(todayKeptURLs.count) / Double(todayOpenedURLs.count),
            feeds: feeds,
            mostKept: mostKept,
            mostSkipped: mostSkipped,
            themeMonths: months,
            themeTrends: themeTrends,
            files: input.files
        )
    }

    #endif

    // MARK: Helpers

    /// A theme rises when the last 3 months hold at least 2 more saves and
    /// a quarter more than the 3 months before; it falls the other way.
    static func trend(_ months: [Int]) -> String {
        guard months.count >= 6 else { return "steady" }
        let recent = months.suffix(3).reduce(0, +)
        let before = months.dropLast(3).suffix(3).reduce(0, +)
        if recent >= before + 2, Double(recent) >= Double(before) * 1.25 { return "rising" }
        if before >= recent + 2, Double(before) >= Double(recent) * 1.25 { return "falling" }
        return "steady"
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func monthKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// The last `n` month keys, oldest first, this month last.
    static func lastMonths(_ n: Int, now: Date, calendar cal: Calendar) -> [String] {
        (0..<n).reversed().compactMap { back in
            cal.date(byAdding: .month, value: -back, to: now).map { monthKey($0, cal) }
        }
    }

    /// The device a file in iCloud Drive/Sift belongs to: "mac-1a2b.json"
    /// → "mac", "iphone-9f.json" → "iphone".
    static func device(ofFile name: String) -> String {
        String(name.split(separator: "-").first ?? "").lowercased()
    }
}
