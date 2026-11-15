import Foundation

/// Substack newsletters: <name>.substack.com/feed. Newsletters on their own
/// domain advertise the same feed, so the web provider finds them.
struct SubstackProvider: FeedProvider {
    let id = "substack"
    let name = "Substack"
    let symbol = "envelope.open"
    let examples = ["name.substack.com", "substack: name"]

    func matches(_ input: String) -> Bool {
        (FeedInput.host(input)?.hasSuffix(".substack.com") ?? false)
            || FeedInput.after(prefixes: ["substack"], in: input) != nil
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        if let name = FeedInput.after(prefixes: ["substack"], in: input) {
            let slug = name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
            return [FeedCandidate(url: "https://\(slug).substack.com/feed")]
        }
        guard let host = FeedInput.host(input) else { return [] }
        return [FeedCandidate(url: "https://\(host)/feed")]
    }
}
