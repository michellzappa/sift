import Foundation

/// How you take in an item: Scan (headlines: HN, Reddit, posts on X,
/// Bluesky, Mastodon, anything short), Watch (video) or Read (long text).
/// One classifier for offered items (Today, feeds) and saved links (the
/// library), so the Scan / Watch / Read switch means the same everywhere.
/// The only overlap is Scan to Read: a headline whose article you open
/// shows in the reader, and once kept with its text it counts as Read.
enum ReadingMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case scan, watch, read

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: "Scan"
        case .watch: "Watch"
        case .read: "Read"
        }
    }

    var symbol: String {
        switch self {
        case .scan: "list.bullet"
        case .watch: "play.rectangle"
        case .read: "book"
        }
    }

    var empty: String {
        switch self {
        case .scan: "No headlines here"
        case .watch: "Nothing to watch here"
        case .read: "Nothing to read here"
        }
    }
}

enum Modes {
    /// Text of this many words or more is a long read: about 3 minutes.
    static let readWords = 600
    static let wordsPerMinute = 220

    /// Feed providers whose items are headlines, whatever text Sift fetches
    /// for them later (the article behind an HN link).
    static let headlineProviders: Set<String> = ["hackernews", "reddit", "news", "bluesky", "mastodon", "github", "arxiv"]

    /// Feed providers whose items are long reads, even when the feed holds
    /// only the opening of a paid post.
    static let readProviders: Set<String> = ["substack", "medium"]

    /// The mode a provider sets for every item that is not a video, if any.
    static func providerMode(_ provider: String?) -> ReadingMode? {
        guard let provider else { return nil }
        if headlineProviders.contains(provider) { return .scan }
        if readProviders.contains(provider) { return .read }
        return nil
    }

    /// Video pages: YouTube (watch, Shorts, youtu.be, live), TikTok,
    /// Instagram reels, Vimeo.
    static func isVideo(_ url: String) -> Bool {
        guard let u = URL(string: url), let host = u.host()?.lowercased() else { return false }
        let path = u.path.lowercased()
        if host == "youtu.be" { return true }
        if host.hasSuffix("youtube.com") {
            return path.hasPrefix("/watch") || path.hasPrefix("/shorts/") || path.hasPrefix("/live/")
        }
        if host.hasSuffix("tiktok.com") || host.hasSuffix("tiktokv.com") { return TikTokReader.videoID(url) != nil }
        if host.hasSuffix("instagram.com") { return path.hasPrefix("/reel/") || path.hasPrefix("/reels/") }
        if host.hasSuffix("vimeo.com") { return path.split(separator: "/").first.map { $0.allSatisfy(\.isNumber) } ?? false }
        return false
    }

    /// Tall video: Shorts, TikTok, reels.
    static func isVertical(_ url: String) -> Bool {
        guard isVideo(url), let u = URL(string: url), let host = u.host()?.lowercased() else { return false }
        return u.path.lowercased().hasPrefix("/shorts/") || host.contains("tiktok") || host.hasSuffix("instagram.com")
    }

    /// Short posts: their text is the headline.
    static func isPost(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host()?.lowercased() else { return false }
        return host == "x.com" || host.hasSuffix(".x.com") || host.hasSuffix("twitter.com") || host == "bsky.app"
            || host.hasSuffix("threads.net") || host.hasSuffix("threads.com")
    }

    /// Word count without making substrings (feed texts run to 60,000
    /// characters and lists ask on every draw).
    static func words(_ text: String?) -> Int {
        guard let text else { return 0 }
        var count = 0, inWord = false
        for b in text.utf8 {
            let space = b == 32 || b == 10 || b == 9 || b == 13
            if space { inWord = false } else if !inWord { inWord = true; count += 1 }
        }
        return count
    }

    /// Minutes of reading, at least 1.
    static func minutes(_ words: Int) -> Int { max(1, Int((Double(words) / Double(wordsPerMinute)).rounded())) }

    /// The mode for one item. `words`: the text Sift has for it.
    /// `provider`: the mode its feed's provider sets (HN: Scan, Substack: Read).
    static func mode(url: String, words: Int, provider: ReadingMode? = nil) -> ReadingMode {
        if isVideo(url) { return .watch }
        if let provider { return provider }
        // A thread on X with a long saved text reads like an article.
        return words >= readWords ? .read : .scan
    }
}
