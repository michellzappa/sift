import Foundation

/// Mastodon and the fediverse: "@user@instance" or an account address
/// gives the account's RSS; "#tag@instance" or an instance's /tags/ page
/// gives the hashtag's RSS.
struct MastodonProvider: FeedProvider {
    let id = "mastodon"
    let name = "Mastodon"
    let symbol = "bubble.left.and.bubble.right"
    let examples = ["@user@mastodon.social", "#swift@mastodon.social"]

    func matches(_ input: String) -> Bool {
        let s = input.trimmingCharacters(in: .whitespaces)
        if s.range(of: #"^@?[\w.]+@[\w.-]+\.[a-z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil, s.hasPrefix("@") { return true }
        if s.range(of: #"^#\w+@[\w.-]+\.[a-z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let parts = FeedInput.path(s)
        return FeedInput.host(s) != nil && (parts.first?.hasPrefix("@") ?? false || parts.first == "tags") && !(FeedInput.host(s)?.hasSuffix("medium.com") ?? false)
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        let s = input.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") {
            let bits = s.dropFirst().split(separator: "@")
            guard bits.count == 2 else { return [] }
            return [FeedCandidate(url: "https://\(bits[1])/tags/\(bits[0]).rss")]
        }
        if s.hasPrefix("@"), !s.contains("/") {
            let bits = s.dropFirst().split(separator: "@")
            guard bits.count == 2 else { return [] }
            return [FeedCandidate(url: "https://\(bits[1])/@\(bits[0]).rss")]
        }
        guard let host = FeedInput.host(s) else { return [] }
        let parts = FeedInput.path(s)
        if parts.first == "tags", parts.count > 1 { return [FeedCandidate(url: "https://\(host)/tags/\(parts[1]).rss")] }
        if let user = parts.first, user.hasPrefix("@") { return [FeedCandidate(url: "https://\(host)/\(user).rss")] }
        return []
    }
}
