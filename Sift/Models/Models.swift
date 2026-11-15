import Foundation

/// One open Safari tab, as iCloud Tabs syncs it to this Mac.
struct SafariTab: Identifiable, Hashable, Sendable {
    /// The URL is the identity: the same link open twice is one tab here.
    var id: String { url }
    let url: String
    let title: String
    let lastViewed: Date?
    /// Where the link came from, shown in the All Sources view: "tabs",
    /// "reading-list", "instagram" or "x".
    var source = "tabs"

    var sourceSymbol: String {
        if source.hasPrefix("import") { return "tray.and.arrow.down" }
        if source.hasPrefix("chrome:") { return "globe" }
        switch source {
        case "reading-list": return "eyeglasses"
        case "instagram": return "camera"
        case "x": return "bookmark"
        case "feeds": return "dot.radiowaves.up.forward"
        default: return "iphone"
        }
    }

    var host: String {
        let h = URL(string: url)?.host() ?? url
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// X and similar sites often sync a bare title such as "x.com".
    var hasUsefulTitle: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t != "X" && t != host && t != "x.com"
    }

    var displayTitle: String { hasUsefulTitle ? title : url }
}

/// A device that syncs tabs through iCloud.
struct SyncedDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tabCount: Int
}

/// A category a tab can go in. Themes are found bottom-up in the user's own
/// links (see `Sorter.discoverThemes`) or added by hand. A non-theme entry is
/// a place where links can end up (a destination), added by hand.
struct Project: Identifiable, Hashable, Codable, Sendable {
    var id: String { name }
    var name: String
    var summary: String
    /// A theme found bottom-up in the user's own links. When themes exist,
    /// they replace repos as the categories Sift sorts into.
    var isTheme: Bool = false
    /// Where a theme's links should go (Starlings projects, repos), as text.
    var destination: String = ""
    /// The user's own words on this theme: why it matters, what they want
    /// from it. Claude reads them when it sorts and rediscovers themes.
    var notes: String = ""
    /// What happened to the theme, one dated line each: found, renamed,
    /// continued from another theme, link counts at each rediscovery.
    var history: [String] = []
    /// The destination this theme's links are sent to by default.
    var sendTo: String?

    init(name: String, summary: String, isTheme: Bool = true, destination: String = "") {
        self.name = name
        self.summary = summary
        self.isTheme = isTheme
        self.destination = destination
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        isTheme = try c.decodeIfPresent(Bool.self, forKey: .isTheme) ?? false
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        history = try c.decodeIfPresent([String].self, forKey: .history) ?? []
        sendTo = try c.decodeIfPresent(String.self, forKey: .sendTo)
    }

    /// Notes and history as one text, for prompts and the search index.
    var memory: String { history.joined(separator: "\n") }

    /// Buckets that are not projects. The sorter may use them too.
    static let personal = "personal"
    static let drop = "drop"
    static let unknown = "unknown"
    /// Transactional tabs: open for a task, not out of curiosity. See `Errands`.
    static let errands = "errands"
    static let buckets = [errands, personal, drop, unknown]

    /// How a theme or bucket is shown. The "drop" bucket is what Claude calls
    /// noise, so it shows as Noise.
    static func displayName(_ name: String) -> String {
        switch name {
        case drop: "Noise"
        case errands: "Errands"
        case personal: "Personal"
        case unknown: "Unknown"
        default: name
        }
    }
}

/// Where a tab was sorted, and why it may matter there.
struct Assignment: Codable, Hashable, Sendable {
    var project: String
    var use: String
    /// True when the user moved the tab by hand. The sorter never overwrites it.
    var manual: Bool
    /// What to do with the link next. Nil until sorted or suggested.
    var action: NextAction?
    /// Other themes this link also feeds. Nil until checked; empty when none.
    var also: [String]? = nil
    /// Who sorted it: "device" (Apple's on-device model) or "claude". Nil for
    /// URL rules and links sorted before this was kept. Kept on a hand move,
    /// so the owner can compare the device's picks with their own.
    var sortedBy: String? = nil
}

/// What to do with a link, so a sorted tab can leave the browser.
enum NextAction: String, Codable, CaseIterable, Hashable, Sendable {
    case read, `try`, cite, contact, file, close

    var label: String {
        switch self {
        case .read: "Read"
        case .try: "Try"
        case .cite: "Cite"
        case .contact: "Contact"
        case .file: "File"
        case .close: "Close"
        }
    }

    var symbol: String {
        switch self {
        case .read: "book"
        case .try: "hammer"
        case .cite: "quote.opening"
        case .contact: "person.crop.circle.badge.plus"
        case .file: "archivebox"
        case .close: "xmark.circle"
        }
    }

    /// The definition Claude sorts by, and the help text in the app.
    var meaning: String {
        switch self {
        case .read: "read or watch it properly: a long article, paper, talk or book"
        case .try: "install, test or prototype with it: a tool, repo, app or method"
        case .cite: "quote or reference it in writing, a deck, a pitch or a spec"
        case .contact: "reach out to the person, company or community behind it"
        case .file: "keep it as reference for the project; nothing to do now"
        case .close: "already used, outdated or not worth more time"
        }
    }
}
