import Foundation
import NaturalLanguage

/// Closeness in meaning with Apple's on-device contextual embeddings
/// (NaturalLanguage, `NLContextualEmbedding`). Compiled into the Mac app
/// (store and jobs: Engine/Embeddings.swift) and the iPhone app
/// (prototypes/ios-deck/project.yml), so both use the same numbers.
/// Measured on the owner's library (2026-11-17, 1,200 links, 27 themes):
/// after subtracting the corpus mean, two links of the same theme have a
/// median cosine of 0.17, two of different themes 0.01 (90th percentile
/// 0.33, 99th 0.59). Good for "near this item"; weak as a theme label (the
/// nearest theme centre is right 35% of the time on held-out links).
enum Meaning {
    static let dim = 512
    /// The store's file format (index.json + vectors.f32).
    static let version = 1
    /// Characters of preview text that go in with the title.
    static let previewChars = 300
    /// Today: a theme fit by meaning needs this cosine to the theme's centre
    /// and this lead over the next theme.
    static let themeMin = 0.45
    static let themeMargin = 0.04

    /// Trails, close in meaning: 6 × (cosine − 0.25), at most 3. Unrelated
    /// links sit near 0 (90% under 0.33), so only close ones count. Words
    /// score 0.6 each (up to 5); a trail takes the larger, never both.
    static func trailScore(_ cos: Double) -> Double { min(max(cos - 0.25, 0) * 6, 3) }

    // Store: `index.json` (model, dim, one url and text hash per row) and
    // `vectors.f32` (little-endian float32, row after row, the raw
    // mean-pooled vectors). Readable without Sift.
    struct Index: Codable {
        var version: Int
        var model: String
        var dim: Int
        var urls: [String]
        var hashes: [String]
    }

    /// Raw vectors by URL, with their text hashes.
    struct Raw: Sendable {
        var vectors: [String: [Float]] = [:]
        var hashes: [String: String] = [:]
        var model = ""
    }

    static func load(from folder: URL) -> Raw {
        let indexURL = folder.appending(path: "index.json")
        guard let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data),
              index.version == version, index.dim == dim,
              let blob = try? Data(contentsOf: folder.appending(path: "vectors.f32")),
              blob.count == index.urls.count * dim * 4 else { return Raw() }
        var raw = Raw(model: index.model)
        blob.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            let floats = p.bindMemory(to: Float.self)
            for (i, url) in index.urls.enumerated() {
                raw.vectors[url] = Array(floats[(i * dim)..<((i + 1) * dim)])
                raw.hashes[url] = index.hashes[i]
            }
        }
        return raw
    }

    static func save(_ raw: Raw, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = raw.vectors.keys.sorted()
        var blob = Data(capacity: urls.count * dim * 4)
        for u in urls { raw.vectors[u]!.withUnsafeBufferPointer { blob.append(Data(buffer: $0)) } }
        let index = Index(version: version, model: raw.model, dim: dim, urls: urls, hashes: urls.map { raw.hashes[$0] ?? "" })
        guard let json = try? JSONEncoder().encode(index) else { return }
        try? blob.write(to: folder.appending(path: "vectors.f32"), options: .atomic)
        try? json.write(to: folder.appending(path: "index.json"), options: .atomic)
    }

    /// The text a link is embedded from.
    static func text(title: String, preview: String) -> String {
        let p = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? title : title + ". " + String(p.prefix(previewChars))
    }

    /// FNV-1a over the text, stable across launches (`hashValue` is not).
    static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// Unit vectors after subtracting the corpus mean, for cosine by dot
    /// product. Theme centres are the normalized mean of their links.
    struct Space: Sendable {
        var unit: [String: [Float]] = [:]
        var mean: [Float] = []
        var themes: [String: [Float]] = [:]
        var isEmpty: Bool { unit.isEmpty }

        init() {}

        init(_ vectors: [String: [Float]], themeOf: [String: String]) {
            guard !vectors.isEmpty else { return }
            var m = [Float](repeating: 0, count: Meaning.dim)
            for v in vectors.values { for i in 0..<Meaning.dim { m[i] += v[i] } }
            let n = Float(vectors.count)
            mean = m.map { $0 / n }
            for (u, v) in vectors { unit[u] = Space.normalize(v, minus: mean) }
            var sums: [String: [Float]] = [:]
            for (u, t) in themeOf {
                guard let v = unit[u] else { continue }
                var s = sums[t] ?? [Float](repeating: 0, count: Meaning.dim)
                for i in 0..<Meaning.dim { s[i] += v[i] }
                sums[t] = s
            }
            for (t, s) in sums { themes[t] = Space.normalize(s, minus: nil) }
        }

        static func normalize(_ v: [Float], minus m: [Float]?) -> [Float] {
            var out = v
            if let m { for i in 0..<out.count { out[i] -= m[i] } }
            var len: Float = 0
            for x in out { len += x * x }
            len = len.squareRoot()
            return len > 0 ? out.map { $0 / len } : out
        }

        static func cos(_ a: [Float], _ b: [Float]) -> Double {
            var d: Float = 0
            for i in 0..<min(a.count, b.count) { d += a[i] * b[i] }
            return Double(d)
        }

        /// A raw vector made now (for an item not in the store) in this space.
        func place(_ raw: [Float]) -> [Float]? {
            mean.isEmpty ? nil : Space.normalize(raw, minus: mean)
        }

        /// The best theme by meaning, if it clearly leads.
        func theme(for v: [Float]) -> (name: String, cos: Double)? {
            let scored = themes.map { ($0.key, Space.cos(v, $0.value)) }.sorted { $0.1 > $1.1 }
            guard let best = scored.first, best.1 >= Meaning.themeMin else { return nil }
            if scored.count > 1, best.1 - scored[1].1 < Meaning.themeMargin { return nil }
            return best
        }
    }
}

/// Apple's model, loaded once per round. Not thread-safe: one round at a
/// time, on one task.
final class Embedder {
    private let model: NLContextualEmbedding
    var identifier: String { model.modelIdentifier }

    /// Nil when the model is not on this Mac (Apple downloads its assets
    /// with the system; Sift asks for them once and waits).
    init?() {
        guard let m = NLContextualEmbedding(language: .english) else { return nil }
        guard m.hasAvailableAssets else {
            m.requestAssets { _, _ in }
            return nil
        }
        guard (try? m.load()) != nil else { return nil }
        model = m
    }

    /// The mean of the token vectors.
    func vector(_ text: String) -> [Float]? {
        guard !text.isEmpty, let r = try? model.embeddingResult(for: text, language: .english) else { return nil }
        var sum = [Double](repeating: 0, count: model.dimension)
        var n = 0.0
        r.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { v, _ in
            for i in 0..<min(v.count, sum.count) { sum[i] += v[i] }
            n += 1
            return true
        }
        guard n > 0, sum.count == Meaning.dim else { return nil }
        return sum.map { Float($0 / n) }
    }
}
