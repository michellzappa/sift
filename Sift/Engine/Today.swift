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
    /// The same link is in two or more of your feeds right now.
    var hot: Bool? = nil
    /// Scan, Watch or Read (`ReadingMode` raw value). Set only in the
    /// phone's today.json (`writeTodayForPhone`), so both apps use one
    /// classifier; nil in state.json.
    var mode: String? = nil
    /// Older than the 3-day window: it came in to fill a mode that had
    /// too few picks (`TodayBuilder.perMode`). Stays until 14 days old.
    var fill: Bool? = nil
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
    /// Unseen items one feed may have in Today at a time. Seen items do not
    /// count, so a feed's next item comes in as you read (owner, 2026-11-15:
    /// Today updates, it does not stop at 10).
    static let perFeed = 3
    /// The ranked part before exploration and the wildcard come in.
    static let size = 10
    /// Picks each mode (Scan, Watch, Read) should have. A mode with fewer
    /// takes unseen items of that mode up to `fillWindowDays` old, so the
    /// Watch tab is not empty on a day the video feeds were quiet.
    static let perMode = 5
    static let fillWindowDays: Double = 14

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
        /// Scan, Watch or Read for a pick (`AppModel.mode(of:feeds:)`, so
        /// the feed's own setting counts).
        var mode: (TodayPick) -> ReadingMode = { Modes.mode(url: $0.url, words: Modes.words($0.content)) }
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
    /// 3. Per mode: a mode with fewer than `perMode` picks takes older
    ///    unseen items of that mode (up to 14 days), then one slot for a
    ///    feed Sift knows little about and one wildcard.
    static func build(_ input: Input, now: Date = Date()) -> [TodayPick] {
        let cutoff = now.addingTimeInterval(-windowDays * 86_400)
        let fillCutoff = now.addingTimeInterval(-fillWindowDays * 86_400)
        let mustCutoff = now.addingTimeInterval(-mustWindowDays * 86_400)
        let keptURLs = Set(input.kept.map(\.url))
        let keptPerFeed = Dictionary(grouping: input.kept.compactMap(\.feedID), by: { $0 }).mapValues(\.count)

        // Hot: the same link in several of your feeds. An item counts for its
        // own address and, for link aggregators (Hacker News, Reddit), for
        // the article it points to.
        var feedsPerURL: [String: Set<String>] = [:]
        var keysOf: [String: Set<String>] = [:]
        for feed in input.feeds where feed.enabled {
            for e in input.entries[feed.id] ?? [] {
                let keys = linkKeys(e)
                keysOf[e.url] = keys
                for k in keys { feedsPerURL[k, default: []].insert(feed.id) }
            }
        }
        let themeWords: [(name: String, words: Set<String>)] = input.themes.map { ($0.name, words($0.name + " " + $0.summary)) }

        struct Candidate { var pick: TodayPick; var score: Double; var priority: FeedPriority; var strong: Bool; var mentions: Int; var mode: ReadingMode; var older: Bool }
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
                      date >= (priority == .must ? mustCutoff : fillCutoff) else { continue }
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
                if let best = themeWords.map({ ($0.name, $0.words.intersection(itemWords).count) }).max(by: { $0.1 < $1.1 }), best.1 >= 3 {
                    score += min(Double(best.1), 4) * 0.15
                    pick.reason = "Fits \(best.0)"
                    strong = true
                }
                let mentions = (keysOf[e.url] ?? [key]).reduce(into: Set<String>()) { $0.formUnion(feedsPerURL[$1] ?? []) }.count
                if mentions > 1 {
                    score += Double(mentions - 1) * 0.6
                    pick.reason = "Hot in \(mentions) of your feeds"
                    pick.hot = true
                    strong = true
                }
                if affinity > 0.4 { strong = true }
                candidates.append(Candidate(pick: pick, score: score, priority: priority, strong: strong, mentions: mentions,
                                            mode: input.mode(pick), older: date < cutoff))
            }
        }

        must.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        // Hot first (most feeds, then score), then the rest by score.
        candidates.sort { ($0.mentions > 1 ? $0.mentions : 0, $0.score) > ($1.mentions > 1 ? $1.mentions : 0, $1.score) }
        var picks = must
        var perFeedCount: [String: Int] = [:]
        for c in candidates where !c.older {
            if c.priority == .best && !c.strong { continue }
            let cap = c.priority == .best ? 1 : perFeed
            guard perFeedCount[c.pick.feedID, default: 0] < cap else { continue }
            perFeedCount[c.pick.feedID, default: 0] += 1
            picks.append(c.pick)
        }
        var modeCount = Dictionary(grouping: picks, by: { input.mode($0) }).mapValues(\.count)

        // Fill: a mode with too few picks takes its older unseen items, best
        // score first (the score already favours newer ones). First within
        // the per-feed share, then past it, so one video channel can fill
        // Watch when it is the only one.
        for mode in ReadingMode.allCases {
            for relaxed in [false, true] where modeCount[mode, default: 0] < perMode {
                for c in candidates where c.older && c.mode == mode && modeCount[mode, default: 0] < perMode {
                    if c.priority == .best && !c.strong { continue }
                    if picks.contains(where: { $0.url == c.pick.url }) { continue }
                    let cap = c.priority == .best ? 1 : perFeed
                    if !relaxed && perFeedCount[c.pick.feedID, default: 0] >= cap { continue }
                    var p = c.pick
                    p.fill = true
                    if p.reason.isEmpty { p.reason = "From the last \(Int(fillWindowDays)) days" }
                    perFeedCount[p.feedID, default: 0] += 1
                    modeCount[mode, default: 0] += 1
                    picks.append(p)
                }
            }
        }

        // Exploration and the wildcard, once per mode, so each tab gets them.
        for mode in ReadingMode.allCases {
            let pool = candidates.filter { $0.mode == mode && !$0.older }
            // Exploration: the newest item of a feed Sift has little evidence on.
            if let explore = pool.first(where: { c in !picks.contains { $0.url == c.pick.url } && c.priority == .normal
                && (input.evidence[c.pick.feedID] ?? 0) < 3 && perFeedCount[c.pick.feedID] == nil }) {
                var p = explore.pick
                if p.reason.isEmpty { p.reason = "New to you" }
                perFeedCount[p.feedID, default: 0] += 1
                picks.append(p)
            }
            // One wildcard, always from a feed not in the digest yet, not
            // from the top scores when there is a choice; none if every
            // feed of this mode is in.
            let used = Set(picks.map(\.feedID))
            let open = pool.filter { !used.contains($0.pick.feedID) }
            if var wild = (open.dropFirst(size).filter({ $0.priority != .best }).randomElement() ?? open.randomElement())?.pick {
                wild.reason = "Something different"
                wild.wildcard = true
                picks.append(wild)
            }
        }
        return picks
    }

    /// Picks from the last update that still belong: their feed is still
    /// followed and in Today, and they are inside the window (Don't Miss
    /// items: 14 days).
    static func stillCurrent(_ picks: [TodayPick], feeds: [Feed], now: Date = Date()) -> [TodayPick] {
        let byID = Dictionary(feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return picks.filter { p in
            guard let feed = byID[p.feedID], feed.enabled, feed.priority != FeedPriority.off.rawValue else { return false }
            let days = feed.priority == FeedPriority.must.rawValue ? mustWindowDays : p.fill == true ? fillWindowDays : windowDays
            return (p.date ?? now) >= now.addingTimeInterval(-days * 86_400)
        }
    }

    /// New picks on top (in rank order), then the old ones in their place.
    /// At most one wildcard per mode at a time.
    static func merge(old: [TodayPick], fresh: [TodayPick], mode: (TodayPick) -> ReadingMode) -> [TodayPick] {
        let oldURLs = Set(old.map(\.url))
        var wildModes = Set(old.filter { $0.wildcard == true }.map(mode))
        var added: [TodayPick] = []
        for p in fresh where !oldURLs.contains(p.url) {
            if p.wildcard == true {
                guard wildModes.insert(mode(p)).inserted else { continue }
            }
            added.append(p)
        }
        return added + old
    }

    /// The keys an item counts under for Hot: its own address and, when its
    /// text links out to another site (a Hacker News or Reddit post), that
    /// article's address.
    static func linkKeys(_ e: FeedEntry) -> Set<String> {
        var keys: Set<String> = [URLKey.normalize(e.url)]
        let own = URL(string: e.url)?.host()?.replacingOccurrences(of: "www.", with: "")
        let aggregators = ["reddit.com", "news.ycombinator.com", "lobste.rs", "redd.it"]
        guard let own, aggregators.contains(where: { own.hasSuffix($0) }), let text = e.content ?? Optional(e.summary) else { return keys }
        let pattern = #"\]\((https?://[^)\s]+)\)|https?://[^\s)\]]+"#
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range
                let link = ns.substring(with: r)
                guard let h = URL(string: link)?.host()?.replacingOccurrences(of: "www.", with: ""),
                      !aggregators.contains(where: { h.hasSuffix($0) }), !h.hasSuffix("redditmedia.com"), !h.hasSuffix("redditstatic.com") else { continue }
                keys.insert(URLKey.normalize(link))
                break
            }
        }
        return keys
    }

    /// Lowercased words of five letters or more, without common ones.
    static func words(_ s: String) -> Set<String> {
        let stop: Set<String> = ["about", "after", "their", "there", "these", "those", "which", "would", "could", "should", "where", "while", "other", "every", "still", "first", "years", "people", "things"]
        return Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 && !stop.contains($0) })
    }
}
