import Foundation

/// Tumblr blogs: <name>.tumblr.com/rss.
struct TumblrProvider: FeedProvider {
    let id = "tumblr"
    let name = "Tumblr"
    let symbol = "t.square"
    let examples = ["name.tumblr.com", "tumblr.com/name"]

    func matches(_ input: String) -> Bool { FeedInput.host(input)?.hasSuffix("tumblr.com") ?? false }

    func candidates(for input: String) async -> [FeedCandidate] {
        guard let host = FeedInput.host(input) else { return [] }
        if host == "tumblr.com", let name = FeedInput.path(input).first {
            return [FeedCandidate(url: "https://\(name).tumblr.com/rss")]
        }
        return [FeedCandidate(url: "https://\(host)/rss")]
    }
}
