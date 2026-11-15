import Foundation

// Today: offered items (feeds now; Bluesky, Mastodon and X people later)
// show only here, as a short digest that ends. Keeping one makes it saved:
// it moves into the "Kept from Today" source and from there into the
// library, themes and search like any other saved link. Offered items not
// kept leave Today when the window passes; they never build a pile.
// Owner decisions 2026-11-15, issues #27 and #30.

/// An offered item the user kept. Stored in state.json (`state.kept`).
struct KeptItem: Codable, Hashable, Sendable, Identifiable {
    var id: String { url }
    var url: String
    var title: String
    var date: Date?
    var kept: Date
    /// The feed it came from, for the row and for ranking.
    var feedID: String?
    var feedTitle: String
    var summary: String
    var image: String?
}

/// One card in the digest, with what the row needs, so Today does not read
/// the feed files to draw.
struct TodayPick: Codable, Hashable, Sendable, Identifiable {
    var id: String { url }
    var url: String
    var title: String
    var date: Date?
    var feedID: String
    var feedTitle: String
    var summary: String
    var image: String?
    /// One line on why it is here: "In 3 of your feeds", "Fits Strategic
    /// Foresight", "You often keep Stratechery", "Something different".
    /// Empty when there is no reason beyond being new.
    var reason: String
    var wildcard = false
    /// The item's full text as Markdown, when the feed carries it.
    var content: String? = nil
    /// A vertical video (a YouTube Short), for the phone's video cards.
    var vertical: Bool? = nil
}

struct TodayDigest: Codable, Hashable, Sendable {
    /// The slot the digest belongs to (07:00 or 17:00).
    var slot: Date
    var built: Date
    var picks: [TodayPick]
}

enum TodayBuilder {
    /// Digest times, local. A new digest replaces the old one at each slot.
    static let slotHours = [7, 17]
    /// Offered items older than this never reach Today.
    static let windowDays: Double = 3
    static let size = 10
    static let perFeed = 2

    /// The latest slot at or before `now`.
    static func currentSlot(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let slots = slotHours.compactMap { cal.date(byAdding: .hour, value: $0, to: today) }.filter { $0 <= now }
        if let last = slots.last { return last }
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        return cal.date(byAdding: .hour, value: slotHours.last!, to: yesterday)!
    }

    static func nextSlot(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for day in 0...1 {
            let base = cal.date(byAdding: .day, value: day, to: today)!
            for h in slotHours {
                let d = cal.date(byAdding: .hour, value: h, to: base)!
                if d > now { return d }
            }
        }
        return now.addingTimeInterval(12 * 3600)
    }

    struct Input {
        var feeds: [Feed]
        var entries: [String: [FeedEntry]]
        /// Theme names with their summaries.
        var themes: [(name: String, summary: String)]
        var kept: [KeptItem]
        var isSeen: (String) -> Bool
        /// Learned weight per feed in -1…1 (FeedSignals.affinity).
        var affinity: [String: Double] = [:]
        /// Signals per feed: few means Sift knows little about it yet.
        var evidence: [String: Int] = [:]
    }

    /// Don't-miss feeds keep their items in Today this long, until seen.
    static let mustWindowDays: Double = 14

    /// Items per day over the last two weeks, over the span the feed's items
    /// actually cover: a feed followed today that holds only its last 30
    /// items (Hacker News: about a day) still reads as busy.
    static func postsPerDay(_ entries: [FeedEntry], now: Date = Date()) -> Double {
        let since = now.addingTimeInterval(-14 * 86_400)
        let dates = entries.compactMap(\.date).filter { $0 >= since && $0 <= now.addingTimeInterval(3600) }
        guard let oldest = dates.min() else { return 0 }
        let days = max(now.timeIntervalSince(oldest) / 86_400, 1)
        return Double(dates.count) / days
    }

    /// The feed's priority: the user's choice, else Auto from its volume.
    static func priority(_ feed: Feed, postsPerDay: Double) -> FeedPriority {
        if let raw = feed.priority, let p = FeedPriority(rawValue: raw) { return p }
        return postsPerDay > FeedPriority.busyPerDay ? .best : .normal
    }

    /// Ranks the unseen, unkept items and picks the digest, like a For You
    /// page for feeds, but finite. Local and cheap: no Claude call.
    /// 1. Every unseen Don't Miss item (14 days), first.
    /// 2. The rest by score: freshness × volume damping (a feed's rare post
    ///    counts more than the 30th of a busy one) × learned affinity, plus
    ///    theme fit and the same link in several feeds. Best Only feeds need
    ///    such a signal and get one slot; Normal feeds two; Not in Today none.
    /// 3. One slot for a feed Sift knows little about, one wildcard.
    static func build(_ input: Input, now: Date = Date()) -> [TodayPick] {
        let cutoff = now.addingTimeInterval(-windowDays * 86_400)
        let mustCutoff = now.addingTimeInterval(-mustWindowDays * 86_400)
        let keptURLs = Set(input.kept.map(\.url))
        let keptPerFeed = Dictionary(grouping: input.kept.compactMap(\.feedID), by: { $0 }).mapValues(\.count)

        var feedsPerURL: [String: Set<String>] = [:]
        for feed in input.feeds where feed.enabled {
            for e in input.entries[feed.id] ?? [] { feedsPerURL[URLKey.normalize(e.url), default: []].insert(feed.id) }
        }
        let themeWords: [(name: String, words: Set<String>)] = input.themes.map { ($0.name, words($0.name + " " + $0.summary)) }

        struct Candidate { var pick: TodayPick; var score: Double; var priority: FeedPriority; var strong: Bool }
        var must: [TodayPick] = []
        var candidates: [Candidate] = []
        var seenURL = Set<String>()
        for feed in input.feeds where feed.enabled {
            let entries = input.entries[feed.id] ?? []
            let rate = postsPerDay(entries, now: now)
            let priority = priority(feed, postsPerDay: rate)
            guard priority != .off else { continue }
            let damping = 1 / sqrt(max(rate, 0.3))
            let affinity = input.affinity[feed.id] ?? 0
            for e in entries {
                guard let date = e.date, date <= now.addingTimeInterval(3600),
                      date >= (priority == .must ? mustCutoff : cutoff) else { continue }
                let key = URLKey.normalize(e.url)
                guard !keptURLs.contains(e.url), !input.isSeen(e.url), seenURL.insert(key).inserted else { continue }
                let title = FeedParser.Text.title(e.title, body: e.summary)
                var pick = TodayPick(url: e.url, title: title.isEmpty ? e.url : title, date: date, feedID: feed.id,
                                     feedTitle: feed.title, summary: e.summary, image: e.image, reason: "", content: e.content)
                if priority == .must { must.append(pick); continue }

                let hours = now.timeIntervalSince(date) / 3600
                var score = exp(-max(hours, 0) / 36) * damping * (1 + 0.8 * affinity)
                var strong = false
                let keeps = keptPerFeed[feed.id] ?? 0
                if affinity > 0.4 || keeps >= 2 { pick.reason = "You often read \(feed.title)" }
                let itemWords = words(e.title + " " + e.summary)
                if let best = themeWords.map({ ($0.name, $0.words.intersection(itemWords).count) }).max(by: { $0.1 < $1.1 }), best.1 >= 2 {
                    score += min(Double(best.1), 4) * 0.15
                    pick.reason = "Fits \(best.0)"
                    strong = true
                }
                let mentions = feedsPerURL[key]?.count ?? 1
                if mentions > 1 {
                    score += Double(mentions - 1) * 0.6
                    pick.reason = "In \(mentions) of your feeds"
                    strong = true
                }
                if affinity > 0.4 { strong = true }
                candidates.append(Candidate(pick: pick, score: score, priority: priority, strong: strong))
            }
        }

        must.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        candidates.sort { $0.score > $1.score }
        var picks = must
        var perFeedCount: [String: Int] = [:]
        let fill = max(size - 2, picks.count)
        for c in candidates where picks.count < fill {
            if c.priority == .best && !c.strong { continue }
            let cap = c.priority == .best ? 1 : perFeed
            guard perFeedCount[c.pick.feedID, default: 0] < cap else { continue }
            perFeedCount[c.pick.feedID, default: 0] += 1
            picks.append(c.pick)
        }
        let taken = Set(picks.map(\.url))
        // Exploration: the newest item of a feed Sift has little evidence on.
        if let explore = candidates.first(where: { !taken.contains($0.pick.url) && $0.priority == .normal
            && (input.evidence[$0.pick.feedID] ?? 0) < 3 && perFeedCount[$0.pick.feedID] == nil }) {
            var p = explore.pick
            if p.reason.isEmpty { p.reason = "New to you" }
            picks.append(p)
        }
        // One wildcard: from a feed not in the digest yet, not the top scores.
        let used = Set(picks.map(\.feedID))
        let urls = Set(picks.map(\.url))
        if var wild = candidates.dropFirst(size).filter({ !used.contains($0.pick.feedID) && $0.priority != .best }).randomElement()?.pick
            ?? candidates.filter({ !urls.contains($0.pick.url) }).randomElement()?.pick {
            wild.reason = "Something different"
            wild.wildcard = true
            picks.append(wild)
        }
        return picks
    }

    /// Lowercased words of five letters or more, without common ones.
    static func words(_ s: String) -> Set<String> {
        let stop: Set<String> = ["about", "after", "their", "there", "these", "those", "which", "would", "could", "should", "where", "while", "other", "every", "still", "first", "years", "people", "things"]
        return Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 && !stop.contains($0) })
    }
}
