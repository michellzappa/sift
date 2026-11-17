import Foundation

/// Meaning on this Mac (owner, 2026-11-17: "lean on local inference wherever
/// we can"). Apple's contextual embedding model (NaturalLanguage,
/// `NLContextualEmbedding`, part of macOS 14+, runs on device) turns each
/// link's title and preview into 512 numbers; links about the same thing get
/// similar numbers. Trails use it for "close in meaning", Today for a soft
/// theme fit. No network, no Claude.
///
/// Measured on the owner's library (2026-11-17, 1,200 links, 27 themes):
/// after subtracting the corpus mean, two links of the same theme have a
/// median cosine of 0.17, two of different themes 0.01 (90th percentile
/// 0.33, 99th 0.59). Good for "near this item"; weak as a theme label (the
/// nearest theme centre is right 35% of the time on held-out links, since
/// the themes overlap). So Today only lifts a pick when one theme clearly
/// wins (`themeMin`, `themeMargin`).
///
/// Files: `Application Support/Sift/embeddings/index.json` (model, dim, one
/// url and text hash per row) and `vectors.f32` (little-endian float32, row
/// after row, the raw mean-pooled vectors). Readable without Sift.
enum Embeddings {
    /// Vectors made per background round (about 15 ms each).
    static let perRound = 2000

    static var folder: URL { StateFile.url.deletingLastPathComponent().appending(path: "embeddings", directoryHint: .isDirectory) }

    static func load() -> Meaning.Raw { Meaning.load(from: folder) }
    static func save(_ raw: Meaning.Raw) { Meaning.save(raw, to: folder) }
}
