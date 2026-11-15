import Foundation

/// Bluesky profiles: every profile has an RSS feed of its posts.
/// "@name.bsky.social", "@name.com" (one @, a dot) or a bsky.app address.
struct BlueskyProvider: FeedProvider {
    let id = "bluesky"
    let name = "Bluesky"
    let symbol = "cloud"
    let examples = ["@name.bsky.social", "bsky.app/profile/name.com"]

    func matches(_ input: String) -> Bool {
        let s = input.trimmingCharacters(in: .whitespaces)
        if FeedInput.host(s) == "bsky.app" { return true }
        return s.hasPrefix("@") && s.filter { $0 == "@" }.count == 1 && s.contains(".") && !s.contains("/")
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        let s = input.trimmingCharacters(in: .whitespaces)
        var handle = s.hasPrefix("@") ? String(s.dropFirst()) : ""
        if FeedInput.host(s) == "bsky.app" {
            let parts = FeedInput.path(s)
            if let i = parts.firstIndex(of: "profile"), parts.count > i + 1 { handle = parts[i + 1] }
        }
        guard !handle.isEmpty else { return [] }
        return [FeedCandidate(url: "https://bsky.app/profile/\(handle)/rss")]
    }
}
