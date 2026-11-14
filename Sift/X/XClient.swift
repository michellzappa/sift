import Foundation

/// One X post as Sift keeps it: everything the native post view needs, and
/// nothing else. Built from X API v2 responses.
struct XPost: Codable, Hashable, Sendable, Identifiable {
    struct Author: Codable, Hashable, Sendable {
        let id: String
        let name: String
        let username: String
        let avatar: String?
    }
    struct Media: Codable, Hashable, Sendable {
        let type: String          // photo, video, animated_gif
        let url: String?          // photos
        let preview: String?      // video poster
        let video: String?        // best MP4 variant
        let alt: String?
        let width: Int?
        let height: Int?
    }
    struct Link: Codable, Hashable, Sendable {
        let start: Int
        let end: Int
        let tco: String
        let display: String
        let expanded: String
        let title: String?
        let summary: String?
        /// Links to the post's own media; the media shows instead.
        let isMedia: Bool
    }
    struct Mention: Codable, Hashable, Sendable { let start: Int; let end: Int; let username: String }
    struct Tag: Codable, Hashable, Sendable { let start: Int; let end: Int; let tag: String }

    let id: String
    let text: String
    let created: Date?
    let author: Author?
    let media: [Media]
    let links: [Link]
    let mentions: [Mention]
    let tags: [Tag]
    let quotedID: String?
    let replyTo: String?
    let edited: Bool
    var fetched: Date
    /// The API no longer returns the post (deleted, private, withheld).
    var removed: Bool = false

    var permalink: String { "https://x.com/\(author?.username ?? "i")/status/\(id)" }

    /// The first link that leaves X, for previews and sorting.
    var outbound: String? { links.first { !$0.isMedia && !($0.expanded.contains("x.com/") || $0.expanded.contains("twitter.com/")) }?.expanded }

    static func removedStub(_ id: String) -> XPost {
        XPost(id: id, text: "", created: nil, author: nil, media: [], links: [], mentions: [], tags: [],
              quotedID: nil, replyTo: nil, edited: false, fetched: .now, removed: true)
    }
}

/// X API v2 calls Sift makes. Every call is billed to the user's own X
/// developer account (pay-per-use), so Sift batches lookups (100 posts per
/// call) and caches results; see `XStore` for refresh rules.
struct XClient: Sendable {
    let clientID: String

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let postFields = "created_at,author_id,entities,attachments,referenced_tweets,in_reply_to_user_id,note_tweet,edit_history_tweet_ids"
    private static let expansions = "author_id,attachments.media_keys,referenced_tweets.id,referenced_tweets.id.author_id,in_reply_to_user_id"
    private static let mediaFields = "type,url,preview_image_url,variants,alt_text,width,height"
    private static let userFields = "name,username,profile_image_url"

    /// Looks up posts by id, up to 100 per call. Returns found posts (and
    /// quoted posts) plus the ids the API no longer returns.
    func lookup(_ ids: [String]) async throws -> (posts: [XPost], missing: [String]) {
        var posts: [XPost] = []
        var missing: [String] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let json = try await get("/2/tweets", query: [
                "ids": batch.joined(separator: ","), "tweet.fields": Self.postFields, "expansions": Self.expansions,
                "media.fields": Self.mediaFields, "user.fields": Self.userFields,
            ])
            let parsed = Self.parse(json)
            posts += parsed
            let found = Set(parsed.map(\.id))
            missing += batch.filter { !found.contains($0) }
        }
        return (posts, missing)
    }

    func me() async throws -> (id: String, username: String) {
        let json = try await get("/2/users/me", query: [:])
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw Failure(message: "X did not return your account.")
        }
        return (id, data["username"] as? String ?? "")
    }

    /// The user's most recent bookmarks (X returns at most 800): their ids
    /// newest first, and every post needed to draw them (quotes included).
    func bookmarks(userID: String) async throws -> (order: [String], posts: [XPost]) {
        var all: [XPost] = []
        var order: [String] = []
        var token: String?
        repeat {
            var query = ["max_results": "100", "tweet.fields": Self.postFields, "expansions": Self.expansions,
                         "media.fields": Self.mediaFields, "user.fields": Self.userFields]
            if let token { query["pagination_token"] = token }
            let json = try await get("/2/users/\(userID)/bookmarks", query: query)
            all += Self.parse(json)
            order += (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            token = (json["meta"] as? [String: Any])?["next_token"] as? String
        } while token != nil && order.count < 800
        return (order, all)
    }

    private func get(_ path: String, query: [String: String]) async throws -> [String: Any] {
        let access = try await XAuth.accessToken(clientID: clientID)
        var c = URLComponents(string: "https://api.x.com" + path)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: c.url!, timeoutInterval: 30)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch status {
        case 200: return json
        case 401: throw Failure(message: "X rejected the sign-in. Connect again in Settings.")
        case 402: throw Failure(message: "Your X developer account has no credits left.")
        case 429: throw Failure(message: "X rate limit reached. Try again in a few minutes.")
        default:
            let detail = json["detail"] as? String ?? json["title"] as? String ?? "HTTP \(status)"
            throw Failure(message: "X API error: \(detail)")
        }
    }

    // MARK: Parsing

    /// Turns a v2 response into posts: the requested ones, then the quoted
    /// posts from `includes`, so quotes can render.
    static func parse(_ json: [String: Any]) -> [XPost] {
        let includes = json["includes"] as? [String: Any] ?? [:]
        var users: [String: XPost.Author] = [:]
        for u in includes["users"] as? [[String: Any]] ?? [] {
            guard let id = u["id"] as? String else { continue }
            let avatar = (u["profile_image_url"] as? String)?.replacingOccurrences(of: "_normal.", with: "_bigger.")
            users[id] = .init(id: id, name: u["name"] as? String ?? "", username: u["username"] as? String ?? "", avatar: avatar)
        }
        var media: [String: XPost.Media] = [:]
        for m in includes["media"] as? [[String: Any]] ?? [] {
            guard let key = m["media_key"] as? String else { continue }
            let variants = (m["variants"] as? [[String: Any]] ?? []).filter { ($0["content_type"] as? String) == "video/mp4" }
            let best = variants.max { ($0["bit_rate"] as? Int ?? 0) < ($1["bit_rate"] as? Int ?? 0) }
            media[key] = .init(type: m["type"] as? String ?? "photo", url: m["url"] as? String,
                               preview: m["preview_image_url"] as? String, video: best?["url"] as? String,
                               alt: m["alt_text"] as? String, width: m["width"] as? Int, height: m["height"] as? Int)
        }
        func post(_ t: [String: Any]) -> XPost? {
            guard let id = t["id"] as? String else { return nil }
            let note = t["note_tweet"] as? [String: Any]
            let text = note?["text"] as? String ?? t["text"] as? String ?? ""
            let entities = (note?["entities"] as? [String: Any]) ?? (t["entities"] as? [String: Any]) ?? [:]
            let links: [XPost.Link] = (entities["urls"] as? [[String: Any]] ?? []).compactMap { u in
                guard let tco = u["url"] as? String else { return nil }
                return .init(start: u["start"] as? Int ?? 0, end: u["end"] as? Int ?? 0, tco: tco,
                             display: u["display_url"] as? String ?? tco, expanded: u["unwound_url"] as? String ?? u["expanded_url"] as? String ?? tco,
                             title: u["title"] as? String, summary: u["description"] as? String, isMedia: u["media_key"] != nil)
            }
            let mentions: [XPost.Mention] = (entities["mentions"] as? [[String: Any]] ?? []).compactMap { m in
                guard let name = m["username"] as? String else { return nil }
                return .init(start: m["start"] as? Int ?? 0, end: m["end"] as? Int ?? 0, username: name)
            }
            let tags: [XPost.Tag] = (entities["hashtags"] as? [[String: Any]] ?? []).compactMap { h in
                guard let tag = h["tag"] as? String else { return nil }
                return .init(start: h["start"] as? Int ?? 0, end: h["end"] as? Int ?? 0, tag: tag)
            }
            let keys = (t["attachments"] as? [String: Any])?["media_keys"] as? [String] ?? []
            let refs = t["referenced_tweets"] as? [[String: Any]] ?? []
            let quoted = refs.first { $0["type"] as? String == "quoted" }?["id"] as? String
            let replyUser = (t["in_reply_to_user_id"] as? String).flatMap { users[$0]?.username }
            let created = (t["created_at"] as? String).flatMap { ISO8601DateFormatter.withFractions.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return XPost(id: id, text: text, created: created, author: (t["author_id"] as? String).flatMap { users[$0] },
                         media: keys.compactMap { media[$0] }, links: links, mentions: mentions, tags: tags,
                         quotedID: quoted, replyTo: replyUser,
                         edited: (t["edit_history_tweet_ids"] as? [String])?.count ?? 1 > 1, fetched: .now)
        }
        let primary = (json["data"] as? [[String: Any]] ?? []).compactMap(post)
        let quotes = (includes["tweets"] as? [[String: Any]] ?? []).compactMap(post)
        return primary + quotes.filter { q in !primary.contains { $0.id == q.id } }
    }

    /// The status id in an X post URL, if it is one.
    static func statusID(_ url: String) -> String? {
        guard let u = URL(string: url), let host = u.host()?.lowercased(),
              ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com", "mobile.x.com"].contains(host) else { return nil }
        let parts = u.pathComponents
        guard let i = parts.firstIndex(of: "status"), parts.count > i + 1 else { return nil }
        let id = parts[i + 1]
        return id.allSatisfy(\.isNumber) ? id : nil
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// Cached posts, in ~/Library/Application Support/Sift/x-posts.json.
///
/// X's developer policy requires stored posts to stay current: deleted,
/// private or withheld posts must go. Sift re-fetches a post when it is shown
/// and its copy is older than `maxAge`, and drops the content of posts the
/// API no longer returns.
enum XStore {
    static let maxAge: TimeInterval = 7 * 24 * 3600

    static var url: URL { StateFile.url.deletingLastPathComponent().appending(path: "x-posts.json") }
    static var bookmarksURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "x-bookmarks.json") }

    static func load() -> [String: XPost] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: XPost].self, from: data)) ?? [:]
    }

    static func save(_ posts: [String: XPost]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(posts) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Bookmark post ids, newest first.
    static func loadBookmarks() -> [String] {
        guard let data = try? Data(contentsOf: bookmarksURL) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func saveBookmarks(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: bookmarksURL, options: .atomic)
    }
}
