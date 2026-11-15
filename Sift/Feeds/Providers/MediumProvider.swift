import Foundation

/// Medium authors and publications: medium.com/feed/@author or
/// medium.com/feed/<publication>.
struct MediumProvider: FeedProvider {
    let id = "medium"
    let name = "Medium"
    let symbol = "text.book.closed"
    let examples = ["medium.com/@author", "medium.com/publication"]

    func matches(_ input: String) -> Bool { FeedInput.host(input)?.hasSuffix("medium.com") ?? false }

    func candidates(for input: String) async -> [FeedCandidate] {
        guard let host = FeedInput.host(input) else { return [] }
        if host != "medium.com" { return [FeedCandidate(url: "https://medium.com/feed/@\(host.replacingOccurrences(of: ".medium.com", with: ""))")] }
        guard let first = FeedInput.path(input).first, first != "feed" else { return [] }
        return [FeedCandidate(url: "https://medium.com/feed/\(first)")]
    }
}
