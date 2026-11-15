import Foundation

/// arXiv categories: "arxiv cs.AI" or an arxiv.org/list/<category> address.
struct ArxivProvider: FeedProvider {
    let id = "arxiv"
    let name = "arXiv"
    let symbol = "doc.text.magnifyingglass"
    let examples = ["arxiv cs.AI", "arxiv.org/list/cs.HC/new"]

    func matches(_ input: String) -> Bool {
        FeedInput.host(input) == "arxiv.org" || FeedInput.after(prefixes: ["arxiv"], in: input) != nil
    }

    func candidates(for input: String) async -> [FeedCandidate] {
        var category = FeedInput.after(prefixes: ["arxiv"], in: input)
        if category == nil, FeedInput.host(input) == "arxiv.org" {
            let parts = FeedInput.path(input)
            if let i = parts.firstIndex(of: "list"), parts.count > i + 1 { category = parts[i + 1] }
        }
        guard let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { return [] }
        return [FeedCandidate(url: "https://rss.arxiv.org/rss/\(c)", label: "arXiv \(c)")]
    }
}
