import Foundation

/// A news search as a feed: "news: words" follows Google News results.
struct GoogleNewsProvider: FeedProvider {
    let id = "news"
    let name = "News search"
    let symbol = "newspaper"
    let examples = ["news: digital sovereignty"]

    func matches(_ input: String) -> Bool { FeedInput.after(prefixes: ["news"], in: input) != nil }

    func candidates(for input: String) async -> [FeedCandidate] {
        guard let q = FeedInput.after(prefixes: ["news"], in: input) else { return [] }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return [FeedCandidate(url: "https://news.google.com/rss/search?q=\(FeedInput.escape(q))&hl=\(lang)&gl=\(region)&ceid=\(region):\(lang)",
                              label: "News: \(q)")]
    }
}
