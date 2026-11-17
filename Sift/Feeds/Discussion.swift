import Foundation

/// The top comments on a Hacker News or Reddit post, for Scan (owner,
/// 2026-11-17: "top hn comments, or reddit comments … in those cards").
/// The Mac fetches them for Today's picks and writes them into today.json;
/// the phone only shows them. Public endpoints, no login, paced by
/// HostGate:
/// - Hacker News: the Algolia search finds the story for an article link
///   (hnrss items link to the article), then the official Firebase API
///   gives the story's comments in the order HN ranks them.
/// - Reddit: the post's comment feed (`.rss?sort=top`). Reddit's JSON
///   answers 403 without a login, and the feed answers 429 quickly, so a
///   429 pauses reddit.com for an hour.
struct DiscussionComment: Codable, Hashable, Sendable {
    var author: String
    var text: String
}

struct Discussion: Codable, Hashable, Sendable {
    /// The discussion page (the HN item or the Reddit post).
    var url: String
    /// "Hacker News" or "r/swift".
    var site: String
    /// Comments in all, when the site says.
    var count: Int?
    var comments: [DiscussionComment]
    var fetched: Date
}

enum Discussions {
    static let perPost = 3
    /// Longest comment text kept, in characters.
    static let maxText = 420

    /// The Reddit post id and subreddit in a URL, if it is a post.
    static func redditPost(_ url: String) -> (sub: String, id: String)? {
        guard let r = url.range(of: #"reddit\.com/r/([^/]+)/comments/([a-z0-9]+)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let parts = url[r].split(separator: "/")
        guard parts.count >= 5 else { return nil }
        return (String(parts[2]), String(parts[4]))
    }

    static func hnItem(_ url: String) -> Int? {
        guard url.contains("news.ycombinator.com/item"),
              let id = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "id" })?.value else { return nil }
        return Int(id)
    }

    /// Whether Sift looks for a discussion for this pick: a Reddit post, an
    /// HN item, or any link from a Hacker News feed.
    static func applies(url: String, provider: String?) -> Bool {
        redditPost(url) != nil || hnItem(url) != nil || provider == "hackernews"
    }

    static func fetch(url: String, provider: String?) async -> Discussion? {
        if let post = redditPost(url) { return await reddit(post) }
        if let id = hnItem(url) { return await hackerNews(id) }
        if provider == "hackernews", let id = await hnStory(for: url) { return await hackerNews(id) }
        return nil
    }

    // MARK: Hacker News

    private struct HNItem: Decodable {
        var by: String?
        var text: String?
        var kids: [Int]?
        var descendants: Int?
        var deleted: Bool?
        var dead: Bool?
    }

    /// The story for an article link: the one with the most comments.
    private static func hnStory(for article: String) async -> Int? {
        var c = URLComponents(string: "https://hn.algolia.com/api/v1/search")!
        c.queryItems = [.init(name: "restrictSearchableAttributes", value: "url"),
                        .init(name: "tags", value: "story"), .init(name: "query", value: article)]
        struct Hits: Decodable { struct Hit: Decodable { var objectID: String; var num_comments: Int?; var url: String? }; var hits: [Hit] }
        guard let data = await get(c.url!, host: "hn.algolia.com"),
              let hits = try? JSONDecoder().decode(Hits.self, from: data).hits else { return nil }
        let key = URLKey.normalize(article)
        return hits.filter { $0.url.map(URLKey.normalize) == key }
            .max { ($0.num_comments ?? 0) < ($1.num_comments ?? 0) }
            .flatMap { Int($0.objectID) }
    }

    private static func hnGet(_ id: Int) async -> HNItem? {
        guard let data = await get(URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json")!, host: "hacker-news.firebaseio.com")
        else { return nil }
        return try? JSONDecoder().decode(HNItem.self, from: data)
    }

    private static func hackerNews(_ id: Int) async -> Discussion? {
        guard let story = await hnGet(id) else { return nil }
        var comments: [DiscussionComment] = []
        for kid in (story.kids ?? []).prefix(perPost + 3) where comments.count < perPost {
            guard let c = await hnGet(kid), c.deleted != true, c.dead != true,
                  let by = c.by, let text = c.text.map(clean), !text.isEmpty else { continue }
            comments.append(DiscussionComment(author: by, text: text))
        }
        return Discussion(url: "https://news.ycombinator.com/item?id=\(id)", site: "Hacker News",
                          count: story.descendants, comments: comments, fetched: Date())
    }

    // MARK: Reddit

    private static func reddit(_ post: (sub: String, id: String)) async -> Discussion? {
        let page = "https://www.reddit.com/r/\(post.sub)/comments/\(post.id)/"
        guard let feedURL = URL(string: page + ".rss?sort=top&depth=1&limit=\(perPost + 3)"),
              let data = await get(feedURL, host: "reddit.com"),
              let parsed = FeedParser.parse(data, base: feedURL) else { return nil }
        // The first entry is the post itself; comments have a longer path.
        let postPath = "/r/\(post.sub)/comments/\(post.id)/".lowercased()
        let comments = parsed.entries.filter { e in
            guard let path = URL(string: e.url)?.path.lowercased(), path.hasPrefix(postPath) else { return false }
            return path.split(separator: "/").count > 5
        }.compactMap { e -> DiscussionComment? in
            let text = clean(e.content ?? e.summary)
            guard !text.isEmpty, text != "[deleted]", text != "[removed]" else { return nil }
            let author = (e.author ?? "").replacingOccurrences(of: "/u/", with: "")
            return DiscussionComment(author: author, text: text)
        }
        return Discussion(url: page, site: "r/\(post.sub)", count: nil,
                          comments: Array(comments.prefix(perPost)), fetched: Date())
    }

    // MARK: Fetching

    private static func get(_ url: URL, host: String) async -> Data? {
        guard await HostGate.shared.admit(host) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Sift (feed reader; +https://github.com/michellzappa/sift)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 429 || http.statusCode == 503 {
            await HostGate.shared.pause(host, seconds: 3600)
            return nil
        }
        return http.statusCode == 200 ? data : nil
    }

    /// Plain text from comment HTML or Markdown: paragraphs as line breaks,
    /// no tags, no link syntax, cut at `maxText`.
    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"<p>|<br\s*/?>"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for (k, v) in ["&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&#x2F;": "/", "&gt;": ">", "&lt;": "<", "&nbsp;": " ", "&amp;": "&"] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        t = t.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > maxText { t = String(t.prefix(maxText)).trimmingCharacters(in: .whitespaces) + "…" }
        return t
    }
}
