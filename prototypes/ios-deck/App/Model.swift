import Foundation
import Observation
import SwiftUI

// The deck.json that export-deck.py writes from the Mac's Sift data.

struct Deck: Codable, Sendable {
    var schema: Int
    var demo: Bool
    var themes: [Theme]
    var items: [Item]
    var synthesis: [Synthesis]
}

struct Theme: Codable, Sendable, Identifiable, Hashable {
    var name: String
    var summary: String
    var hue: Double
    var count: Int
    var id: String { name }
    var color: Color { Color(hue: hue / 360, saturation: 0.55, brightness: 0.78) }
}

struct Item: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var url: String
    var title: String
    var theme: String
    var kind: String
    var site: String
    var author: String?
    var saved: String?
    var duration: Int?
    var summary: String
    var passage: String
    var transcript: String
    var text: String
    var image: String?
    var also: [String]
    var neighbours: [String]
    // Schema 2: optional, so a schema 1 deck still decodes.
    var imageFile: String?
    var video: Video?
    var published: String?
    var words: Int?
    var keyLines: [String]?
    /// X posts: the post itself (export-deck.py), shown as a post, never
    /// as an article. Older decks have none: see `xPost`.
    var post: XPostInfo? = nil

    struct Video: Codable, Sendable, Hashable {
        var provider: String
        var id: String
    }

    struct XPostInfo: Codable, Sendable, Hashable {
        var name: String?
        var handle: String?
        var avatar: String?
        /// ISO 8601.
        var date: String?
        var text: String
        var images: [String]?
    }

    /// An x.com or twitter.com status link.
    var isXPost: Bool {
        url.range(of: #"^https?://(www\.|mobile\.)?(x|twitter)\.com/[^/]+/status/\d+"#, options: .regularExpression) != nil
    }

    /// The post to show for an X link: the deck's, else made from the item.
    var xPost: XPostInfo {
        if let post { return post }
        let parts = URL(string: url)?.pathComponents ?? []
        let handle = parts.firstIndex(of: "status").flatMap { $0 >= 2 ? parts[$0 - 1] : nil }.flatMap { ["i", "web"].contains($0) ? nil : $0 }
        return XPostInfo(name: author, handle: handle, avatar: nil, date: published,
                         text: text.isEmpty ? (passage.isEmpty ? summary : passage) : text,
                         images: image.map { [$0] })
    }

    /// "8 min read" from the word count, or the video length.
    var readTime: String? {
        if let length { return length }
        guard let words, words > 150 else { return nil }
        return "\(max(1, words / 230)) min read"
    }
    var year: String? { published.map { String($0.prefix(4)) } }

    var isVideo: Bool { kind == "video" || site.contains("youtube") }
    var symbol: String {
        switch kind {
        case "video": "play.rectangle"
        case "post": site.contains("instagram") ? "camera" : "text.bubble"
        case "pdf": "doc.richtext"
        default: "doc.text"
        }
    }
    var length: String? {
        guard let duration, duration > 0 else { return nil }
        return duration >= 3600 ? "\(duration / 3600) h \(duration % 3600 / 60) min" : "\(max(1, duration / 60)) min"
    }
    /// What the card shows under the title: transcript before passage before summary.
    var excerpt: String {
        if !transcript.isEmpty { return String(transcript.prefix(420)) + (transcript.count > 420 ? "…" : "") }
        if !passage.isEmpty { return passage }
        return ""
    }
}

struct Synthesis: Codable, Sendable, Hashable {
    var theme: String
    var text: String
    var items: [String]
}

// MARK: - Decisions

enum Decision: String, Codable, Sendable, CaseIterable {
    case keep, letGo, send, later, read, open, seen, unseen

    var label: String {
        switch self {
        case .keep: "Keep"
        case .letGo: "Let go"
        case .send: "Send"
        case .later: "Later"
        case .read: "Read"
        case .open: "Open"
        case .seen: "Seen"
        case .unseen: "Unseen"
        }
    }
    var symbol: String {
        switch self {
        case .keep: "checkmark"
        case .letGo: "xmark"
        case .send: "paperplane"
        case .later: "clock"
        case .read: "book"
        case .open: "safari"
        case .seen: "eye"
        case .unseen: "eye.slash"
        }
    }
    var color: Color {
        switch self {
        case .keep: .green
        case .letGo: .red
        case .send: .blue
        case .later: .orange
        case .read: .purple
        case .open: .teal
        case .seen: .gray
        case .unseen: .blue
        }
    }
}

/// One line in log.jsonl. The prototype only logs; nothing reaches Sift.
struct LogEntry: Codable, Sendable {
    var at: Date
    var mode: String          // deck | stream
    var item: String
    var theme: String
    var decision: Decision
    var note: String?
    var position: Int         // place in the deck or depth in the thread
    var thread: String?
}

@MainActor
@Observable
final class Store {
    var deck: Deck
    var log: [LogEntry] = []
    var sessionStart = Date()
    var error: String?
    /// Newest seen or unseen mark per URL from every device (Sync.swift).
    var seenMarks: [String: SeenMark] = [:]
    /// Marks made on this phone: its own file in iCloud Drive/Sift/seen.
    @ObservationIgnored var ownSeen: [String: SeenMark] = [:]
    @ObservationIgnored var saveTask: Task<Void, Never>?
    /// The iCloud Drive/Sift folder, once the user picked it.
    var connectedFolder: String?
    /// Today from the Mac (Deck/today.json).
    var today: TodayFile?
    /// What this phone kept from Today; written to kept/iphone-<id>.json.
    var keptHere: [KeptItem] = []
    /// The Mac's followed feeds (Deck/feeds.json, FeedsSync.swift).
    var macFeeds: FeedsFile?
    /// Feed requests made on this phone; written to follows/iphone-<id>.json.
    var feedRequests: [PhoneFeedRequest] = []
    /// Meaning vectors for deck items and Today's picks, made on this phone
    /// (Trail.swift, `refreshMeaning`).
    @ObservationIgnored var meaningSpace = Meaning.Space()
    @ObservationIgnored var meaningRunning = false
    /// Custom lanes from the Mac (Deck/lanes.json, Lanes.swift).
    var lanes: LanesFile?
    /// A tab a view asks to show ("themes"); DeckApp switches and clears it.
    var tabRequest: String?
    /// What Sift knows about you, from the Mac (Deck/you.json, You.swift).
    var you: Profile?
    /// Your Graph from the Mac (Deck/creators.json, Graph.swift).
    var creators: CreatorsFile?
    /// What this phone did with Today picks; written to signals/iphone-<id>.json (Signals.swift).
    @ObservationIgnored var signals: [Signal] = []
    @ObservationIgnored var signalTask: Task<Void, Never>?

    private static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var deckURL: URL { documents.appending(path: "deck.json") }
    /// Images that came with an imported Deck folder.
    static var imagesURL: URL { documents.appending(path: "images", directoryHint: .isDirectory) }

    /// A local image for the item, if the Deck folder had one.
    func localImage(_ item: Item) -> URL? {
        guard let name = item.imageFile else { return nil }
        let url = Self.imagesURL.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }
    static var logURL: URL { documents.appending(path: "log.jsonl") }

    init() {
        deck = Store.loadDeck() ?? Deck(schema: 1, demo: true, themes: [], items: [], synthesis: [])
        log = Store.loadLog()
        ownSeen = Store.loadOwnSeen()
        seenMarks = ownSeen
        keptHere = Store.loadKeptHere()
        today = Store.loadToday()
        signals = Store.loadSignalsHere()
        feedRequests = Store.loadFeedRequests()
        macFeeds = Store.loadMacFeeds()
        creators = Store.loadCreators()
        lanes = Store.loadLanes()
        you = Store.loadYou()
        sync()
    }

    var byID: [String: Item] { Dictionary(deck.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    func theme(_ name: String) -> Theme? { deck.themes.first { $0.name == name } }
    func color(_ name: String) -> Color { theme(name)?.color ?? .gray }

    /// Items with a decision other than later or read.
    var decided: Set<String> {
        Set(log.filter { [.keep, .letGo, .send].contains($0.decision) }.map(\.item))
    }

    private static func loadDeck() -> Deck? {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: deckURL), let d = try? decoder.decode(Deck.self, from: data) { return d }
        if let url = Bundle.main.url(forResource: "sample-deck", withExtension: "json"),
           let data = try? Data(contentsOf: url) { return try? decoder.decode(Deck.self, from: data) }
        return nil
    }

    private static func loadLog() -> [LogEntry] {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(LogEntry.self, from: Data($0.utf8)) }
    }

    /// Copies what the user picked in Files: the Deck folder (deck.json and
    /// images/) or a deck.json alone.
    @discardableResult
    func importDeck(from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let fm = FileManager.default
            var jsonURL = url
            if url.hasDirectoryPath {
                jsonURL = url.appending(path: "deck.json")
            }
            guard let data = coordinatedData(jsonURL) else {
                error = "deck.json is still downloading from iCloud. Sift Deck tries again when it next opens."
                return false
            }
            let d = try JSONDecoder().decode(Deck.self, from: data)
            try data.write(to: Self.deckURL, options: .atomic)
            // Images one by one, each downloaded from iCloud if needed.
            if url.hasDirectoryPath {
                let images = url.appending(path: "images", directoryHint: .isDirectory)
                try? fm.createDirectory(at: Self.imagesURL, withIntermediateDirectories: true)
                for name in Set(d.items.compactMap(\.imageFile)) {
                    let to = Self.imagesURL.appending(path: name)
                    if fm.fileExists(atPath: to.path(percentEncoded: false)) { continue }
                    _ = coordinatedCopy(images.appending(path: name), to: to)
                }
            }
            deck = d
            error = nil
            return true
        } catch {
            self.error = "That file is not a deck.json from export-deck.py. \(error.localizedDescription)"
            return false
        }
    }

    func record(_ item: Item, _ decision: Decision, mode: String, position: Int, thread: String? = nil, note: String? = nil) {
        let entry = LogEntry(at: Date(), mode: mode, item: item.id, theme: item.theme, decision: decision,
                             note: note, position: position, thread: thread)
        log.append(entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let line = try? encoder.encode(entry) else { return }
        let data = line + Data("\n".utf8)
        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: Self.logURL)
        }
    }

    func clearLog() {
        log = []
        try? FileManager.default.removeItem(at: Self.logURL)
    }

    // MARK: Deck and thread building

    /// Seven unseen items: one theme, or a spread over themes.
    func deal(theme: String? = nil, size: Int = 7) -> [Item] {
        let done = Set(deck.items.filter { isSeen($0.url) }.map(\.id))
        let pool = deck.items.filter { !done.contains($0.id) && (theme == nil || $0.theme == theme) }
        if theme != nil { return Array(pool.shuffled().prefix(size)) }
        var byTheme = Dictionary(grouping: pool, by: \.theme).mapValues { $0.shuffled() }
        var out: [Item] = []
        while out.count < size, !byTheme.isEmpty {
            for key in byTheme.keys.shuffled() where out.count < size {
                if var list = byTheme[key], let first = list.first {
                    out.append(first)
                    list.removeFirst()
                    byTheme[key] = list.isEmpty ? nil : list
                }
            }
        }
        return out
    }

    /// A thread: start at the theme's best undecided item and walk the
    /// neighbours, depth first, staying near the start. Never changes theme
    /// by itself beyond the neighbours' own links.
    func thread(theme: String, limit: Int = 14) -> [Item] {
        let map = byID
        let done = decided
        let candidates = deck.items.filter { $0.theme == theme && !done.contains($0.id) }
        guard let start = candidates.first(where: { !$0.transcript.isEmpty || !$0.summary.isEmpty }) ?? candidates.first else { return [] }
        var out: [Item] = [start]
        var seen: Set<String> = [start.id]
        var frontier = start.neighbours
        while out.count < limit, !frontier.isEmpty {
            let next = frontier.removeFirst()
            guard !seen.contains(next), !done.contains(next), let item = map[next] else { continue }
            seen.insert(next)
            out.append(item)
            frontier.insert(contentsOf: item.neighbours.filter { !seen.contains($0) }, at: 0)
        }
        return out
    }

    func synthesis(for theme: String) -> Synthesis? { deck.synthesis.first { $0.theme == theme } }

    // MARK: Numbers

    var minutesThisSession: Int { Int(Date().timeIntervalSince(sessionStart) / 60) }
    func count(_ d: Decision, since: Date? = nil) -> Int {
        log.filter { $0.decision == d && (since == nil || $0.at >= since!) }.count
    }
    var weekStart: Date { Calendar.current.date(byAdding: .day, value: -7, to: Date())! }
}
