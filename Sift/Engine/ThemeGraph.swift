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

/// Creators close in meaning, and a personal rank over them.
enum CreatorGraph {
    /// Creators the graph looks at (best score first).
    static let size = 400
    static let similarMin = 0.35
    static let similarShown = 5
    static let damping = 0.85

    struct Node: Sendable {
        var id: String
        var urls: [String]
        var followed: Bool
        var score: Double
    }

    struct Result: Sendable {
        var similar: [String: [(id: String, cos: Double)]] = [:]
        /// 0…1, highest = most central to what you follow and save.
        var rank: [String: Double] = [:]
    }

    /// Each creator's centre in the meaning space (the mean of its saves'
    /// vectors), edges to creators at `similarMin` or closer, and a personal
    /// PageRank that starts from the creators you follow, weighted by score.
    static func build(_ nodes: [Node], vectors: [String: [Float]]) -> Result {
        var centres: [(id: String, v: [Float])] = []
        for n in nodes.prefix(size) {
            let vs = n.urls.compactMap { vectors[$0] }
            guard let first = vs.first else { continue }
            var sum = [Float](repeating: 0, count: first.count)
            for v in vs { for i in 0..<sum.count { sum[i] += v[i] } }
            centres.append((n.id, Meaning.Space.normalize(sum, minus: nil)))
        }
        var result = Result()
        var edges: [String: [(String, Double)]] = [:]
        for i in centres.indices {
            for j in centres.indices where j > i {
                let c = Meaning.Space.cos(centres[i].v, centres[j].v)
                guard c >= similarMin else { continue }
                edges[centres[i].id, default: []].append((centres[j].id, c))
                edges[centres[j].id, default: []].append((centres[i].id, c))
            }
        }
        for (id, list) in edges {
            result.similar[id] = list.sorted { $0.1 > $1.1 }.prefix(similarShown).map { ($0.0, $0.1) }
        }
        // Personal PageRank: restart at followed creators (by score), else at
        // every creator by score.
        let ids = centres.map(\.id)
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
