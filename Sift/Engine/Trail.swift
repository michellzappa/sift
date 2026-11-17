import Foundation

/// Trails (owner, 2026-11-17: "build trails first"). TikTok's sound and
/// hashtag pages, made finite: from any item, "More Like This" opens a short
/// stream of what is near it in your own data: the same creator, the same
/// theme, shared words, and recent items of your feeds. It ends after
/// `size` items. Local and free: no Claude call, nothing leaves the Mac.
/// The iPhone builds its trails with the same rules from the files it has
/// (prototypes/ios-deck/App/Trail.swift): change both together.
enum Trail {
    static let size = 20
    /// At most this many from one creator, so a trail does not become one
    /// channel's back catalogue.
    static let perCreator = 4
    /// Feed items older than this do not join a trail.
    static let offeredDays: Double = 14
    /// A node needs this score to join.
    static let minScore = 1.8
    /// The feed id of saved links in a trail (they have no feed).
    static let savedFeedID = "trail:saved"

    /// One item a trail can use: a saved link or a feed item.
    struct Node: Sendable {
        var url: String
        var title: String
        var site: String
        var summary: String
        var image: String?
        var date: Date?
        var theme: String?
        /// `Creators.key` id: youtube:<channel>, site:<host>, reddit:r/x…
        var creator: String?
        var creatorName: String?
        /// The feed for an offered item; nil for a saved link.
        var feedID: String?
        var content: String? = nil
        /// Unit vector in the meaning space (`Meaning.Space`), if made.
        var vector: [Float]? = nil
    }


    /// How a node relates to the seed, and its score.
    struct Relation: Sendable {
        var sameCreator: Bool
        var sameTheme: Bool
        var sharedWords: Int
        /// Cosine in the meaning space, when both have a vector.
        var similarity: Double?
        /// True when meaning, not shared words, gave the content score.
        var byMeaning: Bool
        var score: Double
    }

    static func relation(_ n: Node, to seed: Node, seedWords: Set<String>) -> Relation {
        let same = n.creator != nil && n.creator == seed.creator
        let theme = n.theme != nil && n.theme == seed.theme
        let shared = TodayBuilder.words(n.title + " " + n.summary).intersection(seedWords).count
        let words = Double(min(shared, 5)) * 0.6
        var sim: Double?
        if let a = n.vector, let b = seed.vector { sim = Meaning.Space.cos(a, b) }
        let meaning = sim.map(Meaning.trailScore) ?? 0
        // Meaning or words, whichever says more; never both.
        var score = max(words, meaning)
        if same { score += 3 }
        if theme { score += 1.5 }
        return Relation(sameCreator: same, sameTheme: theme, sharedWords: shared, similarity: sim, byMeaning: meaning > words, score: score)
    }

    /// The trail from `seed`: unseen nodes by score, at most `perCreator`
    /// per creator, `size` in all. Each carries its reason line.
    static func build(seed: Node, pool: [Node], isSeen: (String) -> Bool) -> [TodayPick] {
        let seedWords = TodayBuilder.words(seed.title + " " + seed.summary)
        let seedKey = URLKey.normalize(seed.url)
        var scored: [(Node, Relation)] = []
        var seenKeys: Set<String> = [seedKey]
        for n in pool {
            guard !isSeen(n.url), seenKeys.insert(URLKey.normalize(n.url)).inserted else { continue }
            let r = relation(n, to: seed, seedWords: seedWords)
            guard r.score >= minScore else { continue }
            scored.append((n, r))
        }
        // Best score first; on a tie, newer first.
        scored.sort { a, b in
            a.1.score == b.1.score ? (a.0.date ?? .distantPast) > (b.0.date ?? .distantPast) : a.1.score > b.1.score
        }
        var perCreator: [String: Int] = [:]
        var out: [TodayPick] = []
        for (n, r) in scored where out.count < size {
            let who = n.creator ?? n.site
            guard perCreator[who, default: 0] < Self.perCreator else { continue }
            perCreator[who, default: 0] += 1
            out.append(TodayPick(url: n.url, title: n.title, date: n.date, feedID: n.feedID ?? savedFeedID,
                                 feedTitle: n.creatorName ?? n.site, summary: n.summary, image: n.image,
                                 reason: reason(n, r), content: n.content))
        }
        return out
    }

    /// "Same creator · 3 words in common", "Same theme: AI agents", "From
    /// your feeds · 2 words in common".
    static func reason(_ n: Node, _ r: Relation) -> String {
        var parts: [String] = []
        if r.sameCreator { parts.append("Same creator") }
        if r.sameTheme, let t = n.theme { parts.append("Same theme: \(t)") }
        if n.feedID != nil, !r.sameCreator { parts.append("From your feeds") }
        if r.byMeaning, let s = r.similarity { parts.append(String(format: "Close in meaning (%.2f)", s)) }
        else if r.sharedWords > 0 { parts.append("\(r.sharedWords) word\(r.sharedWords == 1 ? "" : "s") in common") }
        return parts.joined(separator: " · ")
    }
}

/// A trail the user opened: where it started and what is on it.
struct TrailState: Sendable {
    var seed: Trail.Node
    var picks: [TodayPick]
    /// The seed's creator in Your Graph, when Sift knows one.
    var creatorID: String?
    var followed: Bool
}
