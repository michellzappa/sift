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
    var xClientID: String = ""
    var xUserID: String?
    var xUsername: String?
    /// Opt-in: X post previews from X's unofficial syndication endpoint, which
    /// returns images. Off by default because the endpoint can stop working.
    var xSyndication: Bool = false
    /// The Instagram data export (zip or folder) the user chose in Settings.
    var instagramExportPath: String?

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
        xClientID = try c.decodeIfPresent(String.self, forKey: .xClientID) ?? ""
        xUserID = try c.decodeIfPresent(String.self, forKey: .xUserID)
        xUsername = try c.decodeIfPresent(String.self, forKey: .xUsername)
        xSyndication = try c.decodeIfPresent(Bool.self, forKey: .xSyndication) ?? false
        instagramExportPath = try c.decodeIfPresent(String.self, forKey: .instagramExportPath)
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
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SiftState.self, from: data)
        else { return SiftState() }
        return state
    }

    static func save(_ state: SiftState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
