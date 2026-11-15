import Foundation

/// GitHub repositories: releases, as Atom. "owner/repo" or any repo address.
struct GitHubProvider: FeedProvider {
    let id = "github"
    let name = "GitHub releases"
    let symbol = "shippingbox"
    let examples = ["github.com/owner/repo", "owner/repo"]

    func matches(_ input: String) -> Bool {
        let s = input.trimmingCharacters(in: .whitespaces)
        if FeedInput.host(s) == "github.com" { return FeedInput.path(s).count >= 2 }
        // "owner/repo": two plain words around one slash, no dots.
        return s.range(of: #"^[\w-]+/[\w-]+$"#, options: .regularExpression) != nil
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        let s = input.trimmingCharacters(in: .whitespaces)
        let parts = FeedInput.host(s) == "github.com" ? FeedInput.path(s) : s.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return [] }
        let repo = "\(parts[0])/\(parts[1].replacingOccurrences(of: ".git", with: ""))"
        return [FeedCandidate(url: "https://github.com/\(repo)/releases.atom", label: "\(repo) releases"),
                FeedCandidate(url: "https://github.com/\(repo)/commits.atom", label: "\(repo) commits")]
    }
}
