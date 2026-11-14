import Foundation

/// Everything Sift remembers, as one plain JSON file:
/// ~/Library/Application Support/Sift/state.json
struct SiftState: Codable, Sendable {
    /// Keyed by tab URL.
    var assignments: [String: Assignment] = [:]
    /// Themes, plus any destinations the user added by hand.
    var extraProjects: [Project] = []
    var deviceID: String?
    var backend: Sorter.Backend = .claudeCode
    /// URLs marked to close on the iPhone. Written to iCloud Drive/Sift/close.txt.
    var closeQueue: [String] = []
    /// Last folder or file each exporter wrote to, keyed by exporter id.
    var exportTargets: [String: String] = [:]
    /// The Client ID of the user's own X app (not a secret). Empty: X API off.
    /// Link exports the user imported (Instapaper, Pocket, Pinboard, bookmarks).
    var importedSources: [LinkImporter.Source] = []
    /// Capture new links into the library in the background.
    var autoCapture = true
    /// Fetch YouTube transcripts with youtube-transcript-api when installed.
    var youtubeTranscripts = true
    /// Fetch Instagram post images from the public embed.
    var instagramImages = true
    /// Turn what Instagram reels say into text with yt-dlp and macOS speech.
    var reelTranscripts = true
    /// Ask Claude which links feed a second theme, for the graph's connections.
    var findConnections = true
    /// Duplicates merged by the user: duplicate URL to the URL kept.
    var mergedInto: [String: String] = [:]
    /// Searches kept in the sidebar.
    var savedSearches: [String] = []
    /// Where links can be sent: Starlings projects, Obsidian folders, files.
    var destinations: [Destination] = []
    /// Where each link was sent, keyed by URL.
    var sent: [String: [SentRecord]] = [:]
    /// A sent Safari tab goes on the iPhone close list.
    var closeAfterSend = true
    /// Background jobs a service refused (youtube, reels): when to try again.
    var blockedUntil: [String: Date] = [:]
    /// The current wait per job, in hours; it doubles on each refusal.
    var backoffHours: [String: Double] = [:]
    var xClientID: String = ""
    var xUserID: String?
    var xUsername: String?
    /// Opt-in: X post previews from X's unofficial syndication endpoint, which
    /// returns images. Off by default because the endpoint can stop working.
    var xSyndication: Bool = false
    /// The Instagram data export (zip or folder) the user chose in Settings.
    var instagramExportPath: String?
    /// Setup Guide step ids the user has been shown. nil: this state predates
    /// the guide (AppModel decides between first run and an existing
    /// install). Set it to [] to see the first run again.
    var onboardingSeen: [String]?
    /// Apple's on-device model (`LocalModel`), per feature. Used only when the
    /// model is available on this Mac.
    var localFirstPass = true
    var localSorting = true
    var localSummaries = true
    /// Names the user gave Chrome profiles, keyed by the extension's install id.
    var chromeProfileNames: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try c.decodeIfPresent([String: Assignment].self, forKey: .assignments) ?? [:]
        extraProjects = try c.decodeIfPresent([Project].self, forKey: .extraProjects) ?? []
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID)
        backend = try c.decodeIfPresent(Sorter.Backend.self, forKey: .backend) ?? .claudeCode
        closeQueue = try c.decodeIfPresent([String].self, forKey: .closeQueue) ?? []
        exportTargets = try c.decodeIfPresent([String: String].self, forKey: .exportTargets) ?? [:]
        importedSources = try c.decodeIfPresent([LinkImporter.Source].self, forKey: .importedSources) ?? []
        autoCapture = try c.decodeIfPresent(Bool.self, forKey: .autoCapture) ?? true
        youtubeTranscripts = try c.decodeIfPresent(Bool.self, forKey: .youtubeTranscripts) ?? true
        instagramImages = try c.decodeIfPresent(Bool.self, forKey: .instagramImages) ?? true
        reelTranscripts = try c.decodeIfPresent(Bool.self, forKey: .reelTranscripts) ?? true
        findConnections = try c.decodeIfPresent(Bool.self, forKey: .findConnections) ?? true
        mergedInto = try c.decodeIfPresent([String: String].self, forKey: .mergedInto) ?? [:]
        savedSearches = try c.decodeIfPresent([String].self, forKey: .savedSearches) ?? []
        destinations = try c.decodeIfPresent([Destination].self, forKey: .destinations) ?? []
        sent = try c.decodeIfPresent([String: [SentRecord]].self, forKey: .sent) ?? [:]
        closeAfterSend = try c.decodeIfPresent(Bool.self, forKey: .closeAfterSend) ?? true
        blockedUntil = try c.decodeIfPresent([String: Date].self, forKey: .blockedUntil) ?? [:]
        backoffHours = try c.decodeIfPresent([String: Double].self, forKey: .backoffHours) ?? [:]
        xClientID = try c.decodeIfPresent(String.self, forKey: .xClientID) ?? ""
        xUserID = try c.decodeIfPresent(String.self, forKey: .xUserID)
        xUsername = try c.decodeIfPresent(String.self, forKey: .xUsername)
        xSyndication = try c.decodeIfPresent(Bool.self, forKey: .xSyndication) ?? false
        instagramExportPath = try c.decodeIfPresent(String.self, forKey: .instagramExportPath)
        onboardingSeen = try c.decodeIfPresent([String].self, forKey: .onboardingSeen)
        localFirstPass = try c.decodeIfPresent(Bool.self, forKey: .localFirstPass) ?? true
        localSorting = try c.decodeIfPresent(Bool.self, forKey: .localSorting) ?? true
        localSummaries = try c.decodeIfPresent(Bool.self, forKey: .localSummaries) ?? true
        chromeProfileNames = try c.decodeIfPresent([String: String].self, forKey: .chromeProfileNames) ?? [:]
    }
}

enum StateFile {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Sift", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "state.json")
    }

    static func load() -> SiftState {
        SafeStore.load(url, as: SiftState.self) ?? SiftState()
    }

    static func save(_ state: SiftState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        SafeStore.save(data, to: url)
    }
}
