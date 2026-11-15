import Foundation

/// Any site or feed address: the address itself if it is a feed, else the
/// page's own feed link (`<link rel="alternate">`), else common paths.
/// Always last in `FeedProviders.all`.
struct WebProvider: FeedProvider {
    static let id = "web"
    var id: String { Self.id }
    let name = "Website"
    let symbol = "globe"
    let examples = ["daringfireball.net", "example.com/blog"]

    func matches(_ input: String) -> Bool { FeedInput.url(input) != nil }

    func candidates(for input: String) async -> [FeedCandidate] {
        guard let found = await FeedFetcher.discover(input) else { return [] }
        return [FeedCandidate(url: found.url)]
    }
}
