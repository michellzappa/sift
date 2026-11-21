import Foundation

/// One part of a theme: links close in meaning, with a short name.
struct SubCluster: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var urls: [String]
    var size: Int { urls.count }
    var id: String { name }
}

/// Sub-clusters (owner, 2026-11-21, roadmap 5): a theme often holds several
/// topics. Each theme's saved links are split by meaning (k-means over the
/// unit vectors of Engine/Meaning.swift, cosine) into 2 to 5 parts. Pure
/// code: no AppModel, no model call, no network. Names come from the
/// on-device model (`LocalModel.nameCluster`) in AppModel+SubClusters, else
/// from `fallbackNames` here.
enum SubClusters {
    /// Themes with fewer links that have a vector are not split.
    static let minLinks = 20
    /// About one part per this many links, within `minK`…`maxK`.
    static let linksPerPart = 25
    static let minK = 2
    static let maxK = 5
    static let restarts = 5
    static let rounds = 30
    /// Titles nearest the centre that the model reads to name a part.
    static let titlesForName = 8
    /// A part keeps the old name when this share of its links is the same
    /// (Jaccard), so one new save does not ask the model again.
    static let keepNameOverlap = 0.7

    struct Part: Sendable {
        /// Members, nearest the centre first.
        var urls: [String]
    }

    static func k(for count: Int) -> Int { min(max(count / linksPerPart, minK), maxK) }

    /// The parts of one theme, biggest first. Empty when the theme has fewer
    /// than `minLinks` links with a vector. Deterministic for the same input.
    static func split(_ urls: [String], vectors: [String: [Float]]) -> [Part] {
        let members = Array(Set(urls)).filter { vectors[$0] != nil }.sorted()
        guard members.count >= minLinks else { return [] }
        let vs = members.map { vectors[$0]! }
        let k = k(for: members.count)
        var best: (score: Double, assign: [Int], centres: [[Float]])?
        for r in 0..<restarts {
            var rng = SplitMix(seed: 0x5157_C105 &+ UInt64(r) &* 0x9E37_79B9_7F4A_7C15)
            let (assign, centres, score) = kMeans(vs, k: k, rng: &rng)
            if best == nil || score > best!.score { best = (score, assign, centres) }
        }
        guard let best else { return [] }
        var parts: [Part] = []
        for c in 0..<k {
            let idx = members.indices.filter { best.assign[$0] == c }
            guard !idx.isEmpty else { continue }
            let sorted = idx.sorted { a, b in
                let ca = Meaning.Space.cos(vs[a], best.centres[c]), cb = Meaning.Space.cos(vs[b], best.centres[c])
                return ca == cb ? members[a] < members[b] : ca > cb
            }
            parts.append(Part(urls: sorted.map { members[$0] }))
        }
        return parts.sorted { a, b in a.urls.count == b.urls.count ? a.urls[0] < b.urls[0] : a.urls.count > b.urls.count }
    }

    /// Spherical k-means with k-means++ seeding. Score = sum of each
    /// member's cosine to its centre (higher is tighter).
    private static func kMeans(_ vs: [[Float]], k: Int, rng: inout SplitMix) -> ([Int], [[Float]], Double) {
        var centres: [[Float]] = [vs[Int(rng.next() % UInt64(vs.count))]]
        while centres.count < k {
            let d = vs.map { v in max(0, 1 - centres.map { Meaning.Space.cos(v, $0) }.max()!) }
            let total = d.reduce(0, +)
            guard total > 0 else { break }
            var pick = Double(rng.next() % 1_000_000) / 1_000_000 * total
            var chosen = vs.count - 1
            for (i, x) in d.enumerated() { pick -= x; if pick <= 0 { chosen = i; break } }
            centres.append(vs[chosen])
        }
        var assign = [Int](repeating: -1, count: vs.count)
        for _ in 0..<rounds {
            var moved = false
            for (i, v) in vs.enumerated() {
                var bestC = 0, bestCos = -Double.infinity
                for (c, centre) in centres.enumerated() {
                    let s = Meaning.Space.cos(v, centre)
                    if s > bestCos { bestCos = s; bestC = c }
                }
                if assign[i] != bestC { assign[i] = bestC; moved = true }
            }
            for c in centres.indices {
                var sum = [Float](repeating: 0, count: vs[0].count)
                var n = 0
                for (i, v) in vs.enumerated() where assign[i] == c {
                    n += 1
                    for j in 0..<sum.count { sum[j] += v[j] }
                }
                if n > 0 { centres[c] = Meaning.Space.normalize(sum, minus: nil) }
            }
            if !moved { break }
        }
        var score = 0.0
        for (i, v) in vs.enumerated() { score += Meaning.Space.cos(v, centres[assign[i]]) }
        return (assign, centres, score)
    }

    /// The cache key for a part's name: theme + a hash of its sorted members.
    static func key(theme: String, urls: [String]) -> String {
        theme + "|" + Meaning.hash(urls.sorted().joined(separator: "\n"))
    }

    static func overlap(_ a: [String], _ b: [String]) -> Double {
        let sa = Set(a), sb = Set(b)
        let union = sa.union(sb).count
        return union == 0 ? 0 : Double(sa.intersection(sb).count) / Double(union)
    }

    /// Names without a model: each part's top 2 words by TF-IDF against the
    /// theme's other parts (`Subterms.build`, theme words left out).
    /// `texts`: url → title + preview.
    static func fallbackNames(theme: String, parts: [Part], texts: [String: String]) -> [String] {
        var input: [String: [String]] = [:]
        let keys = parts.indices.map { "\(theme) \($0)" }
        for (i, p) in parts.enumerated() { input[keys[i]] = p.urls.map { texts[$0] ?? "" } }
        let terms = Subterms.build(input)
        return parts.indices.map { i in
            let words = (terms[keys[i]] ?? []).prefix(2).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return words.isEmpty ? "Part \(i + 1)" : words.joined(separator: ", ")
        }
    }

    /// A model's answer as a chip name: one line, 1 to 4 words, no quotes or
    /// end punctuation. Nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’*.:;,!-–— ").union(.whitespaces))
        let words = trimmed.split(separator: " ").prefix(4)
        let name = words.joined(separator: " ")
        return name.isEmpty || name.count > 40 ? nil : name
    }

    /// Unique names within one theme: a repeat gets " 2", " 3".
    static func unique(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { n in
            let c = (seen[n.lowercased()] ?? 0) + 1
            seen[n.lowercased()] = c
            return c == 1 ? n : "\(n) \(c)"
        }
    }
}

/// A small seeded generator, so the same links give the same parts.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Names already asked, and the last parts per theme, so the chips show at
/// launch and the model is not asked again for the same links.
/// File: `Application Support/Sift/subclusters.json`.
struct SubClusterStore: Codable {
    /// `SubClusters.key` → name.
    var names: [String: String] = [:]
    var parts: [String: [SubCluster]] = [:]

    static var fileURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "subclusters.json") }

    static func load() -> SubClusterStore {
        guard let data = try? Data(contentsOf: fileURL) else { return SubClusterStore() }
        return (try? JSONDecoder().decode(SubClusterStore.self, from: data)) ?? SubClusterStore()
    }

    func save() {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        if let data = try? e.encode(self) { try? data.write(to: Self.fileURL, options: .atomic) }
    }
}
