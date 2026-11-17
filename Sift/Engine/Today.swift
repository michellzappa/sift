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
    /// Top comments on a Hacker News or Reddit post (`Discussions`).
    var discussion: Discussion? = nil
    /// The numbers that put it here (`TodayBuilder.build`), shown under
    /// "Why this is here". Nil for picks from before 1.7.2.
    var why: PickWhy? = nil
}

/// How a pick got its place: every factor of the score, so the reader can
/// check the ranking (owner, 2026-11-17: "show the algorithm").
struct PickWhy: Codable, Hashable, Sendable {
    /// dontMiss, ranked, fill, explore or wildcard.
    var slot: String
    var hoursOld: Double
    /// exp(-hours / 36): 1 when new, 0.5 after about a day.
    var freshness: Double
    var postsPerDay: Double
    /// 1 / sqrt(posts a day): a rare post counts more.
    var volume: Double
    /// What you did with this feed before, -1…1.
    var affinity: Double
    var theme: String?
    var themeWords: Int
    var themeBonus: Double
    /// Feeds that carry the same link.
    var mentions: Int
    var hotBonus: Double
    /// Your Graph: the creator and how many of their links you saved.
    var creator: String?
    var creatorSaves: Int
    var creatorBonus: Double
    var score: Double
    /// Theme fit by meaning (Embeddings): cosine to the theme's centre.
    var themeSimilarity: Double? = nil
    /// Directory: who vouched for this feed when you followed it.
    var vouchedBy: [String]? = nil
    var vouchBonus: Double? = nil
    /// Social proof: your feeds whose posts link to this item.
    var linkedBy: [String]? = nil
    var linkedBonus: Double? = nil
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
        /// Your Graph: per feed, the creator it follows and how many of
        /// their links you saved.
        var creators: [String: (name: String, saves: Int)] = [:]
        /// The theme an item is closest to in meaning, when one clearly
        /// leads (`Meaning.Space.theme`).
        var themeByMeaning: (String) -> (name: String, cos: Double)? = { _ in nil }
        /// People: person id per feed. One person's post on several
        /// platforms shows once, and a person never counts as "Linked by"
        /// for their own items.
        var personOf: [String: String] = [:]
    }

    /// Directory: a feed followed because people you follow vouch for it gets
    /// 0.1 × log2(1 + vouchers), at most 0.3, for its first `vouchDays`.
    static let vouchDays: Double = 30
    static func vouchBonus(_ n: Int) -> Double { min(0.1 * log2(1 + Double(n)), 0.3) }

    /// Markdown and bare links in an item's text.
    static func outLinks(_ e: FeedEntry) -> Set<String> {
        let text = e.content ?? e.summary
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var out = Set<String>()
        for m in NextDoor.linkPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out.insert(URLKey.normalize(ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?*_"))))
        }
        return out
    }

    /// Theme lift by meaning: 2 × (cosine − 0.35), at most 0.6. Only when the
    /// cosine is at least `Meaning.themeMin` and leads the next theme.
    static func meaningBonus(_ cos: Double) -> Double { min(max(cos - 0.35, 0) * 2, 0.6) }

    /// Social proof (owner, 2026-11-17): each other feed of yours whose
    /// post links to an item adds this, up to `linkedMaxBonus`.
    static let linkedBonusEach = 0.3
    static let linkedMaxBonus = 0.9
    /// A link that is in no feed becomes a pick of its own when this many
    /// of your feeds link to it, at most `linkedMaxPicks` per build.
    static let linkedMinFeeds = 2
    static let linkedMaxPicks = 3
    /// Posts that count as linking: the last week.
    static let linkedDays: Double = 7

    /// One address your feeds link to from their posts.
    struct Linked {
        var url: String
        var text: String
        var context: String
        /// Feed id → feed title, for each feed whose post links here.
        var feeds: [String: String] = [:]
        var newest: Date
        var firstFeed: String
    }

    /// The outbound links in your feeds' posts of the last week, by
    /// normalized address. A post's link to its own site, link aggregators
    /// (they count as Hot), shops, sponsors and tip jars do not count.
    static func linked(_ input: Input, now: Date) -> [String: Linked] {
        let since = now.addingTimeInterval(-linkedDays * 86_400)
        let aggregators = ["reddit.com", "news.ycombinator.com", "lobste.rs", "redd.it", "news.google.com"]
        let pattern = try! NSRegularExpression(pattern: #"\[([^\]]{0,200})\]\((https?://[^)\s]+)\)"#)
        var out: [String: Linked] = [:]
        for feed in input.feeds where feed.enabled {
            let feedHost = (URL(string: feed.site ?? feed.url)?.host() ?? "").replacingOccurrences(of: "www.", with: "")
            if aggregators.contains(where: { feedHost.hasSuffix($0) }) { continue }
            for e in input.entries[feed.id] ?? [] {
                guard let date = e.date, date >= since, date <= now.addingTimeInterval(3600),
                      let text = e.content, !text.isEmpty else { continue }
                let own = (URL(string: e.url)?.host() ?? "").replacingOccurrences(of: "www.", with: "")
                let ns = text as NSString
                var seenHere = Set<String>()
                for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let link = ns.substring(with: m.range(at: 2))
                    guard let u = URL(string: link), let h0 = u.host()?.lowercased() else { continue }
                    let host = h0.replacingOccurrences(of: #"^(www\.|m\.)"#, with: "", options: .regularExpression)
                    if host == own || host == feedHost || host.hasSuffix("." + own) || own.hasSuffix("." + host) { continue }
                    if aggregators.contains(where: { host.hasSuffix($0) }) { continue }
                    if NextDoor.noise.contains(host) || NextDoor.noise.contains(where: { host.hasSuffix("." + $0) }) { continue }
                    if u.path.isEmpty || u.path == "/" { continue }
                    if link.range(of: #"\.(png|jpe?g|gif|webp|svg|mp3|mp4|pdf)$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
                    if NextDoor.promo.firstMatch(in: link, range: NSRange(location: 0, length: (link as NSString).length)) != nil { continue }
                    let line = ns.lineRange(for: m.range)
                    if NextDoor.sponsorLine.firstMatch(in: text, range: line) != nil { continue }
                    let key = URLKey.normalize(link)
                    guard seenHere.insert(key).inserted else { continue }
                    let anchor = ns.substring(with: m.range(at: 1))
                    let context = ns.substring(with: line)
                        .replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
                        .replacingOccurrences(of: #"[*_`>#]"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if out[key] == nil {
                        out[key] = Linked(url: link, text: anchor, context: String(context.prefix(280)), newest: date, firstFeed: feed.id)
                    }
                    out[key]!.feeds[feed.id] = feed.title
                    if date > out[key]!.newest {
                        out[key]!.newest = date
                        out[key]!.firstFeed = feed.id
                        out[key]!.context = String(context.prefix(280))
                        if anchor.count > out[key]!.text.count { out[key]!.text = anchor }
                    }
                }
            }
        }
        return out
    }

    /// "Linked by A", "Linked by A and B", "Linked by A, B and 2 more".
    static func linkedReason(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: "Linked by \(names[0])"
        case 2: "Linked by \(names[0]) and \(names[1])"
        default: "Linked by \(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }

    /// Score bonus for a creator you saved `saves` links from.
    static func creatorBonus(_ saves: Int) -> Double { min(0.12 * log2(1 + Double(saves)), 0.6) }

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
        let linkedMap = linked(input, now: now)
        // Cross-posts: a person's post that only points to their own item on
        // another platform (a Bluesky post for a new video) is left out; the
        // item itself stays.
        var personItems: [String: Set<String>] = [:]
        for feed in input.feeds where feed.enabled {
            guard let person = input.personOf[feed.id] else { continue }
            for e in input.entries[feed.id] ?? [] { personItems[person, default: []].insert(URLKey.normalize(e.url)) }
        }
        func isCrossPost(_ e: FeedEntry, feed: String) -> Bool {
            guard let person = input.personOf[feed], let own = personItems[person] else { return false }
            let key = URLKey.normalize(e.url)
            return !outLinks(e).filter { $0 != key && own.contains($0) }.isEmpty
        }
        let themeWords: [(name: String, words: Set<String>)] = input.themes.map { ($0.name, words($0.name + " " + $0.summary)) }

        struct Candidate { var pick: TodayPick; var score: Double; var priority: FeedPriority; var strong: Bool; var mentions: Int; var mode: ReadingMode; var older: Bool
                           var linked = false }
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
                guard !keptURLs.contains(e.url), !input.isSeen(e.url), !isCrossPost(e, feed: feed.id), seenURL.insert(key).inserted else { continue }
                let title = FeedParser.Text.title(e.title, body: e.summary)
                var pick = TodayPick(url: e.url, title: title.isEmpty ? e.url : title, date: date, feedID: feed.id,
                                     feedTitle: feed.title, summary: e.summary, image: e.image, reason: "", content: e.content)
                let hours = now.timeIntervalSince(date) / 3600
                let creator = input.creators[feed.id]
                var why = PickWhy(slot: "ranked", hoursOld: max(hours, 0), freshness: exp(-max(hours, 0) / 36), postsPerDay: rate,
                                  volume: damping, affinity: affinity, theme: nil, themeWords: 0, themeBonus: 0, mentions: 1, hotBonus: 0,
                                  creator: creator?.name, creatorSaves: creator?.saves ?? 0, creatorBonus: creatorBonus(creator?.saves ?? 0), score: 0)
                if priority == .must {
                    why.slot = "dontMiss"
                    pick.why = why
                    must.append(pick)
                    continue
                }

                var score = why.freshness * damping * (1 + 0.8 * affinity) + why.creatorBonus
                if let by = feed.vouchedBy, !by.isEmpty, let at = feed.vouchedAt, now.timeIntervalSince(at) < vouchDays * 86_400 {
                    why.vouchedBy = by
                    why.vouchBonus = vouchBonus(by.count)
                    score += vouchBonus(by.count)
                    pick.reason = by.count == 1 ? by[0] : "\(by[0]) and \(by.count - 1) more"
                }
                var strong = false
                let keeps = keptPerFeed[feed.id] ?? 0
                if affinity > 0.4 || keeps >= 2 { pick.reason = "You often read \(feed.title)" }
                if let creator, creator.saves >= 3 {
                    pick.reason = "You saved \(creator.saves) from \(creator.name)"
                    if creator.saves >= 5 { strong = true }
                }
                let itemWords = words(e.title + " " + e.summary)
                if let best = themeWords.map({ ($0.name, $0.words.intersection(itemWords).count) }).max(by: { $0.1 < $1.1 }), best.1 >= 3 {
                    why.theme = best.0
                    why.themeWords = best.1
                    why.themeBonus = min(Double(best.1), 4) * 0.15
                    score += why.themeBonus
                    pick.reason = "Fits \(best.0)"
                    strong = true
                }
                // By meaning, on this Mac: counts when it lifts more than words.
                if let m = input.themeByMeaning(e.url), meaningBonus(m.cos) > why.themeBonus {
                    score += meaningBonus(m.cos) - why.themeBonus
                    why.theme = m.name
                    why.themeSimilarity = m.cos
                    why.themeBonus = meaningBonus(m.cos)
                    pick.reason = "Fits \(m.name)"
                    strong = true
                }
                // Social proof: other feeds of yours whose posts link here.
                var linkers: [String: String] = [:]
                for k in keysOf[e.url] ?? [key] {
                    for (id, title) in linkedMap[k]?.feeds ?? [:] where id != feed.id {
                        if let me = input.personOf[feed.id], input.personOf[id] == me { continue }
                        linkers[id] = title
                    }
                }
                if !linkers.isEmpty {
                    let names = linkers.values.sorted()
                    why.linkedBy = names
                    why.linkedBonus = min(Double(names.count) * linkedBonusEach, linkedMaxBonus)
                    score += why.linkedBonus ?? 0
                    pick.reason = linkedReason(names)
                    strong = true
                }
                let mentions = (keysOf[e.url] ?? [key]).reduce(into: Set<String>()) { $0.formUnion(feedsPerURL[$1] ?? []) }.count
                why.mentions = mentions
                if mentions > 1 {
                    why.hotBonus = Double(mentions - 1) * 0.6
                    score += why.hotBonus
                    pick.reason = "Hot in \(mentions) of your feeds"
                    pick.hot = true
                    strong = true
                }
                if affinity > 0.4 { strong = true }
                why.score = score
                pick.why = why
                candidates.append(Candidate(pick: pick, score: score, priority: priority, strong: strong, mentions: mentions,
                                            mode: input.mode(pick), older: date < cutoff))
            }
        }

        // Social proof picks: a link that two or more of your feeds point to
        // but no feed carries as an item. Its own place, at most
        // `linkedMaxPicks`; the post that linked it most recently gives the
        // summary.
        for (key, l) in linkedMap where Set(l.feeds.keys.map { input.personOf[$0] ?? $0 }).count >= linkedMinFeeds && feedsPerURL[key] == nil {
            guard l.newest >= cutoff, !keptURLs.contains(l.url), !input.isSeen(l.url), seenURL.insert(key).inserted else { continue }
            let host = (URL(string: l.url)?.host() ?? "").replacingOccurrences(of: "www.", with: "")
            let generic = ["here", "this", "link", "post", "article", "read more", "source", "via", "paper", "thread"]
            let anchor = l.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = anchor.count >= 12 && !generic.contains(anchor.lowercased()) ? anchor : host + (URL(string: l.url)?.path ?? "")
            let names = l.feeds.values.sorted()
            let hours = max(now.timeIntervalSince(l.newest) / 3600, 0)
            let bonus = min(Double(names.count) * linkedBonusEach, linkedMaxBonus)
            let why = PickWhy(slot: "linked", hoursOld: hours, freshness: exp(-hours / 36), postsPerDay: 0, volume: 1, affinity: 0,
                              theme: nil, themeWords: 0, themeBonus: 0, mentions: 0, hotBonus: 0, creator: nil, creatorSaves: 0,
                              creatorBonus: 0, score: exp(-hours / 36) + bonus, linkedBy: names, linkedBonus: bonus)
            var pick = TodayPick(url: l.url, title: title, date: l.newest, feedID: l.firstFeed, feedTitle: host,
                                 summary: l.context, image: nil, reason: linkedReason(names))
            pick.why = why
            candidates.append(Candidate(pick: pick, score: why.score, priority: .normal, strong: true, mentions: 0,
                                        mode: input.mode(pick), older: false, linked: true))
        }

        must.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        // Hot first (most feeds, then score), then the rest by score.
        candidates.sort { ($0.mentions > 1 ? $0.mentions : 0, $0.score) > ($1.mentions > 1 ? $1.mentions : 0, $1.score) }
        var picks = must
        var perFeedCount: [String: Int] = [:]
        var linkedPicks = 0
        for c in candidates where !c.older {
            if c.linked {
                // Social proof picks have their own cap, not the feed's.
                guard linkedPicks < linkedMaxPicks else { continue }
                linkedPicks += 1
                picks.append(c.pick)
                continue
            }
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
                    p.why?.slot = "fill"
                    if p.reason.isEmpty { p.reason = "From the last \(Int(fillWindowDays)) days" }
                    perFeedCount[p.feedID, default: 0] += 1
                    modeCount[mode, default: 0] += 1
                    picks.append(p)
                }
            }
        }

        // Exploration and the wildcard, once per mode, so each tab gets them.
        for mode in ReadingMode.allCases {
            let pool = candidates.filter { $0.mode == mode && !$0.older && !$0.linked }
            // Exploration: the newest item of a feed Sift has little evidence on.
            if let explore = pool.first(where: { c in !picks.contains { $0.url == c.pick.url } && c.priority == .normal
                && (input.evidence[c.pick.feedID] ?? 0) < 3 && perFeedCount[c.pick.feedID] == nil }) {
                var p = explore.pick
                p.why?.slot = "explore"
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
                wild.why?.slot = "wildcard"
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
