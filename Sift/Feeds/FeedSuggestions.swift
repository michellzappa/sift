import Foundation

/// Feeds to follow, with evidence, from what the user already saves: sites
/// they save from again and again, subreddits and GitHub repositories their
/// links point into. Bounded and local: no directory, no network until the
/// user clicks Follow. Issue #28.
struct FeedSuggestion: Identifiable, Hashable, Sendable {
    var id: String { input }
    /// What goes into the Follow field: "tradition.st", "r/swift", "owner/repo".
    var input: String
    var label: String
    var providerID: String
    /// "You saved 7"
    var evidence: String
    var count: Int
}

enum FeedSuggestions {
    /// Platforms whose host says nothing about a person's interests, or that
    /// have no feeds. Their links still count through subreddits and repos.
    static let skipHosts: Set<String> = [
        "x.com", "twitter.com", "instagram.com", "facebook.com", "tiktok.com", "linkedin.com", "threads.net", "threads.com",
        "youtube.com", "youtu.be", "google.com", "docs.google.com", "drive.google.com", "maps.google.com",
        "apple.com", "apps.apple.com", "amazon.com", "t.co", "bit.ly", "github.com", "reddit.com",
        "wikipedia.org", "en.wikipedia.org", "localhost", "chatgpt.com", "claude.ai", "notion.so", "figma.com",
    ]

    /// Up to `limit` suggestions, most evidence first. `followed` holds the
    /// hosts and inputs already followed.
    static func make(urls: [String], followedHosts: Set<String>, followedInputs: Set<String>, limit: Int = 12) -> [FeedSuggestion] {
        var hosts: [String: Int] = [:]
        var subreddits: [String: Int] = [:]
        var repos: [String: Int] = [:]
        for raw in urls {
            guard let u = URL(string: raw), let h = u.host()?.lowercased() else { continue }
            let host = h.replacingOccurrences(of: #"^(www\.|m\.|old\.)"#, with: "", options: .regularExpression)
            let parts = u.pathComponents.filter { $0 != "/" }
            if host.hasSuffix("reddit.com"), parts.count >= 2, parts[0] == "r" {
                subreddits["r/" + parts[1].lowercased(), default: 0] += 1
            } else if host == "github.com", parts.count >= 2, !["orgs", "settings", "notifications", "search", "topics", "features", "marketplace"].contains(parts[0]) {
                repos["\(parts[0])/\(parts[1])", default: 0] += 1
            } else if !skipHosts.contains(host), !skipHosts.contains(where: { host.hasSuffix("." + $0) }) {
                hosts[host, default: 0] += 1
            }
        }
        var out: [FeedSuggestion] = []
        for (host, n) in hosts where n >= 3 && !followedHosts.contains(host) {
            let provider = FeedProviders.match(host)
            out.append(FeedSuggestion(input: host, label: host, providerID: provider.id, evidence: "You saved \(n)", count: n))
        }
        for (sub, n) in subreddits where n >= 2 && !followedInputs.contains(sub) {
            out.append(FeedSuggestion(input: sub, label: sub, providerID: "reddit", evidence: "You saved \(n) from it", count: n))
        }
        for (repo, n) in repos where n >= 2 && !followedInputs.contains(repo.lowercased()) {
            out.append(FeedSuggestion(input: repo, label: repo, providerID: "github", evidence: "You saved \(n) links to it", count: n))
        }
        return Array(out.sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }.prefix(limit))
    }
}
