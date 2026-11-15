import Foundation

/// Hacker News: the front page (news.ycombinator.com/rss), or "hn: words"
/// for new stories that match, through hnrss.org.
struct HackerNewsProvider: FeedProvider {
    let id = "hackernews"
    let name = "Hacker News"
    let symbol = "y.square"
    let examples = ["hn", "hn: local-first"]

    func matches(_ input: String) -> Bool {
        let s = input.lowercased().trimmingCharacters(in: .whitespaces)
        return s == "hn" || s == "hacker news" || FeedInput.host(s) == "news.ycombinator.com"
            || FeedInput.after(prefixes: ["hn"], in: input) != nil
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        if let q = FeedInput.after(prefixes: ["hn"], in: input) {
            return [FeedCandidate(url: "https://hnrss.org/newest?q=\(FeedInput.escape(q))", label: "Hacker News: \(q)")]
        }
        return [FeedCandidate(url: "https://news.ycombinator.com/rss", label: "Hacker News front page")]
    }
}
