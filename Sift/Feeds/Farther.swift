import Foundation

/// Farther (owner, 2026-11-17: "claude suggestions per theme"). The third
/// way to extend a theme, after Your Graph (deeper) and Next Door (the
/// people your people link to): the user's own Claude reads where a theme
/// is going and names sources one step beyond it. Sift then checks each
/// suggestion for a feed, so nothing unfollowable is shown as followable.
/// On request only, one theme at a time. Sends the theme's name, summary,
/// history, newest saved titles and the creators already followed to the
/// user's own Claude (Claude Code login or API key), as sorting does; the
/// exact text is kept with the answer and shown in the app.

struct FartherSuggestion: Codable, Hashable, Sendable, Identifiable {
    var id: String { input.lowercased() }
    var name: String
    /// What Follow takes: a site, youtube.com/@handle, r/name, @x.bsky.social…
    var input: String
    /// video, writing, podcast or community.
    var kind: String
    /// One sentence that ties it to the theme's direction.
    var why: String
    /// deeper (the same direction, further), adjacent (a neighbouring field
    /// the saves lean toward) or counter (a strong opposing view).
    var step: String
    /// nil: not checked yet; true: a feed was found; false: none.
    var hasFeed: Bool? = nil
    var feedTitle: String? = nil
    var lastPost: Date? = nil
}

struct FartherResult: Codable, Hashable, Sendable {
    var theme: String
    var asked: Date
    /// The direction Claude read in the saves, one sentence.
    var direction: String
    var suggestions: [FartherSuggestion]
    /// Exactly what was sent, for "What Claude saw".
    var prompt: String
}

enum Farther {
    static let count = 8
    static let titles = 30

    static var fileURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "farther.json") }

    static func load() -> [String: FartherResult] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? d.decode([String: FartherResult].self, from: data)) ?? [:]
    }

    static func save(_ all: [String: FartherResult]) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? e.encode(all) { try? data.write(to: fileURL, options: .atomic) }
    }

    static let system = """
        You help a person read further in the direction their interests are already moving. You get one of \
        their themes: its name and summary, how it changed, the titles they saved most recently (newest first), \
        and the creators they already follow or save from.

        First, say in one sentence where the theme is going: what the newest saves lean toward compared with \
        the summary. Then name \(count) sources they do not follow yet, one step beyond what they have:
        - "deeper": the same direction, further or more expert.
        - "adjacent": a neighbouring field the newest saves point toward.
        - "counter": one strong, serious opposing or different view.
        Give at least one adjacent and one counter. Prefer individual writers, researchers, newsletters, \
        podcasts and YouTube channels that publish regularly and have a feed, over big publications. \
        Never name anything in the "already" list. For "input", give what a feed reader can follow: the \
        site's domain (example.com), a Substack domain, youtube.com/@handle, r/subreddit, or \
        "podcast: Name". Only name sources you are confident exist. For "why", one sentence that names \
        what in their saves it continues.
        """

    static var schema: [String: Any] { [
        "type": "object", "additionalProperties": false, "required": ["direction", "sources"],
        "properties": [
            "direction": ["type": "string"],
            "sources": ["type": "array", "items": [
                "type": "object", "additionalProperties": false,
                "required": ["name", "input", "kind", "why", "step"],
                "properties": [
                    "name": ["type": "string"],
                    "input": ["type": "string"],
                    "kind": ["type": "string", "enum": ["video", "writing", "podcast", "community"]],
                    "why": ["type": "string"],
                    "step": ["type": "string", "enum": ["deeper", "adjacent", "counter"]],
                ],
            ]],
        ],
    ] }

    /// The user text for one theme.
    static func prompt(theme: Project, titles: [String], creators: [String], already: [String]) -> String {
        var lines = ["Theme: \(theme.name)", "Summary: \(theme.summary)"]
        if !theme.history.isEmpty { lines.append("How it changed:\n" + theme.history.suffix(5).map { "- \($0)" }.joined(separator: "\n")) }
        lines.append("Newest saves:\n" + titles.prefix(Self.titles).map { "- \($0)" }.joined(separator: "\n"))
        if !creators.isEmpty { lines.append("Creators they save from most in this theme: " + creators.joined(separator: ", ")) }
        lines.append("Already (do not suggest): " + already.joined(separator: ", "))
        return lines.joined(separator: "\n\n")
    }

    static func ask(backend: Sorter.Backend, prompt: String, theme: String) async throws -> FartherResult {
        struct Answer: Decodable {
            struct S: Decodable { var name, input, kind, why, step: String }
            var direction: String
            var sources: [S]
        }
        let a = try await Sorter.ask(backend: backend, system: system, user: prompt, schema: schema, as: Answer.self)
        var seen = Set<String>()
        let list = a.sources.compactMap { s -> FartherSuggestion? in
            let input = s.input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty, seen.insert(input.lowercased()).inserted else { return nil }
            return FartherSuggestion(name: s.name, input: input, kind: s.kind, why: s.why, step: s.step)
        }
        return FartherResult(theme: theme, asked: Date(), direction: a.direction, suggestions: list, prompt: prompt)
    }

    /// Looks for each suggestion's feed with the Follow providers.
    static func check(_ s: FartherSuggestion) async -> FartherSuggestion {
        var out = s
        if let found = await FeedProviders.resolve(s.input).first {
            out.hasFeed = true
            out.feedTitle = found.label ?? found.parsed.title
            out.lastPost = found.parsed.entries.compactMap(\.date).max()
        } else {
            out.hasFeed = false
        }
        return out
    }
}
