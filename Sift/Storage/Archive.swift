import Foundation

/// Sift's memory of every link it has seen. A link gets a record the first
/// time a source shows it, the record follows its theme, use and next action,
/// and when the link leaves its source (a tab closed on the phone, an item
/// removed from the Reading List or an export) the record stays, marked
/// archived. Nothing Sift learned about a link is lost when the tab goes.
///
/// Stored as plain JSON in ~/Library/Application Support/Sift/archive.json.
struct ArchiveRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String { url }
    let url: String
    var title: String
    var source: String
    var theme: String?
    var use: String
    var action: NextAction?
    var previewText: String
    var imageURL: String?
    var firstSeen: Date
    var lastSeen: Date
    /// When the link left its source; nil while it is still there.
    var archived: Date?
    /// For later: one line on what the link taught, written or confirmed by the user.
    var takeaway: String?

    var isArchived: Bool { archived != nil }

    init(url: String, title: String, source: String, firstSeen: Date) {
        self.url = url
        self.title = title
        self.source = source
        self.use = ""
        self.previewText = ""
        self.firstSeen = firstSeen
        self.lastSeen = firstSeen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "tabs"
        theme = try c.decodeIfPresent(String.self, forKey: .theme)
        use = try c.decodeIfPresent(String.self, forKey: .use) ?? ""
        action = try c.decodeIfPresent(NextAction.self, forKey: .action)
        previewText = try c.decodeIfPresent(String.self, forKey: .previewText) ?? ""
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        firstSeen = try c.decodeIfPresent(Date.self, forKey: .firstSeen) ?? .now
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? firstSeen
        archived = try c.decodeIfPresent(Date.self, forKey: .archived)
        takeaway = try c.decodeIfPresent(String.self, forKey: .takeaway)
    }

    /// The record as a link Sift can show as a card.
    var asTab: SafariTab {
        var t = SafariTab(url: url, title: title, lastViewed: archived ?? lastSeen)
        t.source = source
        return t
    }
}

enum ArchiveStore {
    static var url: URL { StateFile.url.deletingLastPathComponent().appending(path: "archive.json") }

    static func load() -> [String: ArchiveRecord] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: ArchiveRecord].self, from: data)) ?? [:]
    }

    static func save(_ records: [String: ArchiveRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
