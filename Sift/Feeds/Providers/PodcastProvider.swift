import Foundation

/// Podcasts. A podcast is a feed already; Apple's public directory finds it.
/// An Apple Podcasts address (id lookup) or "podcast: name" (search, up to
/// five results to pick from).
struct PodcastProvider: FeedProvider {
    let id = "podcast"
    let name = "Podcast"
    let symbol = "mic"
    let examples = ["podcast: name of the show", "podcasts.apple.com/…/id123"]

    func matches(_ input: String) -> Bool {
        FeedInput.host(input) == "podcasts.apple.com" || FeedInput.after(prefixes: ["podcast"], in: input) != nil
    }

    private struct Lookup: Decodable {
        struct Result: Decodable { var feedUrl: String?; var collectionName: String?; var artistName: String? }
        var results: [Result]
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        var api: String
        if let term = FeedInput.after(prefixes: ["podcast"], in: input) {
            api = "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=5&term=\(FeedInput.escape(term))"
        } else if let r = input.range(of: #"id(\d+)"#, options: .regularExpression) {
            api = "https://itunes.apple.com/lookup?id=\(input[r].dropFirst(2))"
        } else {
            return []
        }
        guard let url = URL(string: api), let (data, _) = try? await URLSession.shared.data(from: url),
              let found = try? JSONDecoder().decode(Lookup.self, from: data) else { return [] }
        return found.results.compactMap { r in
            r.feedUrl.map { FeedCandidate(url: $0, label: [r.collectionName, r.artistName].compactMap { $0 }.joined(separator: " · ")) }
        }
    }
}
