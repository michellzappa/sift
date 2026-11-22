import Foundation

/// On-device intelligence for themes and creators (owner, 2026-11-17,
/// roadmap 3: "lean on local inference"). Plain counting and the meaning
/// vectors Sift already has; no model call, no network.

/// Subterms: the words that set one theme apart from the others, by
/// TF-IDF over the titles and previews of its saved links.
enum Subterms {
    static let perTheme = 8
    /// A word needs this many links in the theme.
    static let minLinks = 3
    /// Words that summaries and titles use for any topic (tested on the
    /// owner's library, 2026-11-21: "explores", "discusses", "video" ranked
    /// high in most themes).
    static let filler: Set<String> = [
        "explores", "explore", "discusses", "discuss", "discussion", "video", "videos", "using", "shares", "through",
        "including", "features", "feature", "describes", "highlights", "provides", "offers", "focuses", "covers",
        "includes", "examines", "presents", "explains", "talks", "interview", "episode", "article", "author",
        "visit", "watch", "learn", "learning", "today", "really", "great", "based", "different", "important",
        "discover", "insights", "guide", "introduction", "overview", "share", "check", "subscribe", "channel",
    ]

    /// theme → texts (title + preview) of its links.
    static func build(_ texts: [String: [String]]) -> [String: [String]] {
        var df: [String: Int] = [:]
        var perTheme: [String: [String: Int]] = [:]
        for (theme, list) in texts {
            var counts: [String: Int] = [:]
            for t in list { for w in TodayBuilder.words(t) { counts[w, default: 0] += 1 } }
            perTheme[theme] = counts
            for w in counts.keys { df[w, default: 0] += 1 }
        }
        let n = Double(max(texts.count, 1))
        var out: [String: [String]] = [:]
        for (theme, counts) in perTheme {
            let own = TodayBuilder.words(theme)
            var scored: [(w: String, s: Double)] = []
            for (w, c) in counts where c >= minLinks && !own.contains(w) && !filler.contains(w) {
                let idf = log(1 + n / Double(df[w] ?? 1))
                scored.append((w, Double(c) * idf))
            }
            scored.sort { a, b in a.s == b.s ? a.w < b.w : a.s > b.s }
            var top: [String] = []
            for item in scored.prefix(Self.perTheme) { top.append(item.w) }
            out[theme] = top
        }
        return out
    }
}

/// Creators close in meaning or saved together, and a personal rank over
/// them (issue #44: co-save edges).
enum CreatorGraph {
    /// Creators the graph looks at (best score first).
    static let size = 400
    static let similarMin = 0.35
    static let similarShown = 5
    static let damping = 0.85
    /// Co-save edges: each theme-week two creators share adds this much,
    /// up to `coSaveMax`.
    static let coSaveStep = 0.15
    static let coSaveMax = 0.6
    /// A theme-week with more creators than this is a bulk import: skipped.
    static let coSaveCrowd = 20

    struct Node: Sendable {
        var id: String
        var saves: [CreatorSave]
        var followed: Bool
        var score: Double
    }

    /// One edge as "Close to" shows it.
    struct Near: Sendable {
        var id: String
        /// Cosine of the two meaning centres; 0 when under `similarMin` or
        /// when a creator has no vector.
        var cos: Double
        /// Theme-weeks in which both creators were saved.
        var weeks: Int
        /// cos + co-save weight. "Close to" and the rank use this.
        var weight: Double
    }

    struct Result: Sendable {
        var similar: [String: [Near]] = [:]
        /// 0…1, highest = most central to what you follow and save.
        var rank: [String: Double] = [:]
    }

    /// The co-save weight for a number of shared theme-weeks.
    static func coSaveWeight(_ weeks: Int) -> Double { min(coSaveMax, coSaveStep * Double(weeks)) }

    /// "theme|year-week" (ISO 8601 weeks) → creators saved in it.
    static func themeWeeks(_ nodes: [Node]) -> [String: Set<String>] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        var out: [String: Set<String>] = [:]
        for n in nodes {
            for s in n.saves {
                guard let t = s.theme else { continue }
                let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.date)
                guard let y = c.yearForWeekOfYear, let w = c.weekOfYear else { continue }
                out["\(t)|\(y)-\(w)", default: []].insert(n.id)
            }
        }
        return out
    }

    /// Each creator's centre in the meaning space (the mean of its saves'
    /// vectors), meaning edges at `similarMin` or closer, co-save edges for
    /// creators saved in the same theme in the same week, and a personal
    /// PageRank that starts from the creators you follow, weighted by score.
    static func build(_ nodes: [Node], vectors: [String: [Float]]) -> Result {
        let graphNodes = Array(nodes.prefix(size))
        var centres: [(id: String, v: [Float])] = []
        for n in graphNodes {
            let vs = n.saves.compactMap { vectors[$0.url] }
            guard let first = vs.first else { continue }
            var sum = [Float](repeating: 0, count: first.count)
            for v in vs { for i in 0..<sum.count { sum[i] += v[i] } }
            centres.append((n.id, Meaning.Space.normalize(sum, minus: nil)))
        }
        struct Pair: Hashable { var a: String; var b: String }
        func pair(_ x: String, _ y: String) -> Pair { x < y ? Pair(a: x, b: y) : Pair(a: y, b: x) }
        var cosOf: [Pair: Double] = [:]
        for i in centres.indices {
            for j in centres.indices where j > i {
                let c = Meaning.Space.cos(centres[i].v, centres[j].v)
                if c >= similarMin { cosOf[pair(centres[i].id, centres[j].id)] = c }
            }
        }
        var weeksOf: [Pair: Int] = [:]
        for (_, members) in themeWeeks(graphNodes) where members.count >= 2 && members.count <= coSaveCrowd {
            let m = members.sorted()
            for i in m.indices { for j in m.indices where j > i { weeksOf[pair(m[i], m[j]), default: 0] += 1 } }
        }
        var result = Result()
        var edges: [String: [(String, Double)]] = [:]
        for p in Set(cosOf.keys).union(weeksOf.keys) {
            let c = cosOf[p] ?? 0, w = weeksOf[p] ?? 0
            let weight = c + coSaveWeight(w)
            guard weight > 0 else { continue }
            edges[p.a, default: []].append((p.b, weight))
            edges[p.b, default: []].append((p.a, weight))
            result.similar[p.a, default: []].append(Near(id: p.b, cos: c, weeks: w, weight: weight))
            result.similar[p.b, default: []].append(Near(id: p.a, cos: c, weeks: w, weight: weight))
        }
        for (id, list) in result.similar {
            result.similar[id] = Array(list.sorted { $0.weight == $1.weight ? $0.id < $1.id : $0.weight > $1.weight }.prefix(similarShown))
        }
        // Personal PageRank: restart at followed creators (by score), else at
        // every creator by score.
        let ids = graphNodes.map(\.id)
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var restart: [String: Double] = [:]
        for id in ids { if let n = byID[id], n.followed { restart[id] = 1 + n.score } }
        if restart.isEmpty { for id in ids { restart[id] = byID[id]?.score ?? 0 } }
        let total = restart.values.reduce(0, +)
        guard total > 0 else { return result }
        for k in restart.keys { restart[k]! /= total }
        var rank = restart
        for _ in 0..<20 {
            var next: [String: Double] = [:]
            for (k, v) in restart { next[k] = (1 - damping) * v }
            for id in ids {
                guard let r = rank[id], r > 0, let out = edges[id], !out.isEmpty else { continue }
                let w = out.reduce(0) { $0 + $1.1 }
                for (to, c) in out { next[to, default: 0] += damping * r * c / w }
            }
            rank = next
        }
        let top = rank.values.max() ?? 1
        result.rank = rank.mapValues { $0 / top }
        return result
    }
}
