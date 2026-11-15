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
    var reason: String
    var wildcard = false
    /// The item's full text as Markdown, when the feed carries it.
    var content: String? = nil
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
    }

    /// Ranks the window's unseen, unkept items and picks the digest. Local
    /// and cheap: no Claude call.
    static func build(_ input: Input, now: Date = Date()) -> [TodayPick] {
        let cutoff = now.addingTimeInterval(-windowDays * 86_400)
        let keptURLs = Set(input.kept.map(\.url))
        let keptPerFeed = Dictionary(grouping: input.kept.compactMap(\.feedID), by: { $0 }).mapValues(\.count)

        // The same link in several feeds is what people are talking about.
        var feedsPerURL: [String: Set<String>] = [:]
        for feed in input.feeds where feed.enabled {
            for e in input.entries[feed.id] ?? [] { feedsPerURL[URLKey.normalize(e.url), default: []].insert(feed.id) }
        }

        let themeWords: [(name: String, words: Set<String>)] = input.themes.map { t in
            (t.name, words(t.name + " " + t.summary))
        }

        struct Candidate { var pick: TodayPick; var score: Double }
        var candidates: [Candidate] = []
        var seenURL = Set<String>()
        for feed in input.feeds where feed.enabled {
            for e in input.entries[feed.id] ?? [] {
                guard let date = e.date, date >= cutoff, date <= now.addingTimeInterval(3600) else { continue }
                let key = URLKey.normalize(e.url)
                guard !keptURLs.contains(e.url), !input.isSeen(e.url), seenURL.insert(key).inserted else { continue }

                let hours = now.timeIntervalSince(date) / 3600
                var score = exp(-max(hours, 0) / 36)
                var reason = "New from \(feed.title)"

                let keeps = keptPerFeed[feed.id] ?? 0
                if keeps > 0 {
                    score += min(Double(keeps), 6) * 0.12
                    if keeps >= 2 { reason = "You often keep \(feed.title)" }
                }

                let itemWords = words(e.title + " " + e.summary)
                if let best = themeWords.map({ ($0.name, $0.words.intersection(itemWords).count) }).max(by: { $0.1 < $1.1 }), best.1 >= 2 {
                    score += min(Double(best.1), 4) * 0.15
                    reason = "Fits \(best.0)"
                }

                let mentions = feedsPerURL[key]?.count ?? 1
                if mentions > 1 {
                    score += Double(mentions - 1) * 0.6
                    reason = "In \(mentions) of your feeds"
                }

                candidates.append(Candidate(pick: TodayPick(
                    url: e.url, title: FeedParser.Text.title(e.title, body: e.summary).isEmpty ? e.url : FeedParser.Text.title(e.title, body: e.summary), date: date, feedID: feed.id,
                    feedTitle: feed.title, summary: e.summary, image: e.image, reason: reason,
                    content: e.content), score: score))
            }
        }

        candidates.sort { $0.score > $1.score }
        var picks: [TodayPick] = []
        var perFeedCount: [String: Int] = [:]
        for c in candidates where picks.count < size - 1 {
            guard perFeedCount[c.pick.feedID, default: 0] < perFeed else { continue }
            perFeedCount[c.pick.feedID, default: 0] += 1
            picks.append(c.pick)
        }
        // One wildcard: from a feed not in the digest yet, not the top scores.
        let used = Set(picks.map(\.feedID))
        if var wild = candidates.dropFirst(size).filter({ !used.contains($0.pick.feedID) }).randomElement()?.pick
            ?? candidates.filter({ !picks.map(\.url).contains($0.pick.url) }).randomElement()?.pick {
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
