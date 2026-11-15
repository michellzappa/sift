import Foundation

/// Subreddits, users and any Reddit page: Reddit serves RSS at <page>/.rss.
struct RedditProvider: FeedProvider {
    let id = "reddit"
    let name = "Reddit"
    let symbol = "bubble.left.and.text.bubble.right"
    let examples = ["r/swift", "u/username", "reddit.com/r/apple/top"]

    func matches(_ input: String) -> Bool {
        let s = input.lowercased()
        return s.range(of: #"^/?(r|u|user)/[\w-]+"#, options: .regularExpression) != nil
            || (FeedInput.host(input)?.hasSuffix("reddit.com") ?? false)
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: #"^/?(r|u|user)/"#, options: [.regularExpression, .caseInsensitive]) != nil {
            s = "https://www.reddit.com/" + s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard var url = FeedInput.url(s), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        c.host = "www.reddit.com"
        var path = c.path
        if path.hasPrefix("/u/") { path = "/user/" + path.dropFirst(3) }
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix(".rss") { path += "/.rss" }
        c.path = path
        url = c.url ?? url
        return [FeedCandidate(url: url.absoluteString)]
    }
}
