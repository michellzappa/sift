import Foundation

/// The social networks Sift knows from a link alone, with no network call.
/// One place for the Mac and the phone (the phone's project.yml compiles
/// this file). ADR 0001, decision 5: Sift likes and saves only on Bluesky
/// and Mastodon; links to the other networks open in their own app.
enum Networks {
    /// "Instagram", "TikTok", "X" or "YouTube" for a link that opens in its
    /// own app. Nil for every other link.
    static func appName(for url: String) -> String? {
        guard let host = host(url) else { return nil }
        if matches(host, "instagram.com") { return "Instagram" }
        if matches(host, "tiktok.com") { return "TikTok" }
        if matches(host, "x.com") || matches(host, "twitter.com") { return "X" }
        if matches(host, "youtube.com") || matches(host, "youtu.be") { return "YouTube" }
        return nil
    }

    /// The author (handle or DID) and record key of a Bluesky post link,
    /// bsky.app/profile/<actor>/post/<rkey>.
    static func blueskyPost(_ url: String) -> (actor: String, rkey: String)? {
        guard let u = URL(string: url), let host = host(url), host == "bsky.app" else { return nil }
        let parts = u.path().split(separator: "/").map(String.init)
        guard parts.count == 4, parts[0] == "profile", parts[2] == "post", !parts[1].isEmpty, !parts[3].isEmpty else { return nil }
        return (parts[1].removingPercentEncoding ?? parts[1], parts[3])
    }

    /// True for a Mastodon status link: /@user/<id> (also /@user@host/<id>)
    /// or /users/<user>/statuses/<id>. Other Fediverse servers that use the
    /// same paths count too; the person's own instance resolves them.
    static func isMastodonStatus(_ url: String) -> Bool {
        guard let u = URL(string: url), u.scheme == "https", let host = host(url), host != "bsky.app",
              appName(for: url) == nil else { return false }
        let parts = u.path().split(separator: "/").map(String.init)
        if parts.count == 2, parts[0].hasPrefix("@"), parts[0].count > 1, parts[1].allSatisfy(\.isNumber) { return true }
        if parts.count == 4, parts[0] == "users", parts[2] == "statuses", parts[3].allSatisfy(\.isNumber) { return true }
        return false
    }

    private static func host(_ url: String) -> String? {
        guard var h = URL(string: url)?.host()?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "mobile."] where h.hasPrefix(prefix) { h.removeFirst(prefix.count) }
        return h
    }

    private static func matches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
