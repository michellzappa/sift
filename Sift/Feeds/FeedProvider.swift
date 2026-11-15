import Foundation

// MARK: - Adding a feed provider
//
// A provider turns what a person types or pastes (a handle, an address, a
// name) into feed addresses. Sift then fetches and checks each one.
//
// 1. Create Sift/Feeds/Providers/<Name>Provider.swift with a struct that
//    conforms to `FeedProvider`.
// 2. Add one instance to `FeedProviders.all`, before `WebProvider` (the
//    catch-all, always last).
// That is all: the Add sheet, the match hint, fetching, Today and the
// sidebar come for free. A provider may ask the network only in
// `candidates` (for example to look up a channel id), never in `matches`.
// See CONTRIBUTING.md for the checklist.

/// One feed address a provider proposes, with a label when there are
/// several (podcast search results, for example).
struct FeedCandidate: Sendable, Hashable {
    var url: String
    var label: String?
}

protocol FeedProvider: Sendable {
    /// Stable and lowercase. Stored on the feed (`Feed.provider`).
    var id: String { get }
    /// "Reddit", "YouTube".
    var name: String { get }
    /// SF Symbol for the sidebar and the Add sheet.
    var symbol: String { get }
    /// What people can type, shown as hints: "r/swift", "@name.bsky.social".
    var examples: [String] { get }
    /// No network: true when the input looks like this provider's.
    func matches(_ input: String) -> Bool
    /// Feed addresses to try, best first. May ask the network.
    func candidates(for input: String) async -> [FeedCandidate]
}

enum FeedProviders {
    /// Order matters: specific providers first, `WebProvider` last.
    static let all: [any FeedProvider] = [
        RedditProvider(),
        YouTubeProvider(),
        SubstackProvider(),
        BlueskyProvider(),
        MastodonProvider(),
        MediumProvider(),
        TumblrProvider(),
        GitHubProvider(),
        PodcastProvider(),
        HackerNewsProvider(),
        GoogleNewsProvider(),
        ArxivProvider(),
        WebProvider(),
    ]

    static func provider(id: String?) -> (any FeedProvider)? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// The first provider whose `matches` is true (the web as a last resort).
    static func match(_ input: String) -> any FeedProvider {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { $0.matches(s) } ?? WebProvider()
    }

    /// A feed that Sift fetched and parsed, ready to follow.
    struct Found: Sendable {
        var provider: String
        var url: String
        var label: String?
        var parsed: FeedParser.Parsed
    }

    /// Asks the matching provider for candidates, then fetches and parses
    /// each one. Falls back to web discovery when none parse.
    static func resolve(_ input: String) async -> [Found] {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return [] }
        let provider = match(s)
        var found: [Found] = []
        for c in await provider.candidates(for: s).prefix(8) {
            guard let url = URL(string: c.url), let parsed = await fetch(url) else { continue }
            found.append(Found(provider: provider.id, url: c.url, label: c.label, parsed: parsed))
        }
        if found.isEmpty, provider.id != WebProvider.id, let web = await FeedFetcher.discover(s) {
            found.append(Found(provider: WebProvider.id, url: web.url, label: nil, parsed: web.parsed))
        }
        return found
    }

    static func fetch(_ url: URL) async -> FeedParser.Parsed? {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("Sift (feed reader; +https://github.com/michellzappa/sift)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400 else { return nil }
        return FeedParser.parse(data, base: url)
    }
}

/// Helpers the providers share.
enum FeedInput {
    /// The input as a URL: adds https:// when there is no scheme.
    static func url(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.contains(".") || t.contains("://") else { return nil }
        return URL(string: t.contains("://") ? t : "https://" + t)
    }

    /// Host without "www." and "m.", lowercased.
    static func host(_ s: String) -> String? {
        guard let h = url(s)?.host()?.lowercased() else { return nil }
        return h.replacingOccurrences(of: #"^(www\.|m\.)"#, with: "", options: .regularExpression)
    }

    /// Path parts of the input URL, without empty ones.
    static func path(_ s: String) -> [String] {
        url(s)?.pathComponents.filter { $0 != "/" && !$0.isEmpty } ?? []
    }

    /// The text after a "word:" or "word " prefix, if the input has it.
    static func after(prefixes: [String], in s: String) -> String? {
        let lower = s.lowercased()
        for p in prefixes {
            for sep in [":", " "] where lower.hasPrefix(p + sep) {
                let rest = s.dropFirst(p.count + 1).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return rest }
            }
        }
        return nil
    }

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? s
    }
}
