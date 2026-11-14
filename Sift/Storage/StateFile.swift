import Foundation

/// Everything Sift remembers, as one plain JSON file:
/// ~/Library/Application Support/Sift/state.json
struct SiftState: Codable, Sendable {
    /// Keyed by tab URL.
    var assignments: [String: Assignment] = [:]
    /// Projects the user added that have no repo (for example a research theme).
    var extraProjects: [Project] = []
    /// Repo names the user hid from the project list.
    var hiddenProjects: [String] = []
    var projectsRoot: String = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Dev").path(percentEncoded: false)
    var deviceID: String?
    var backend: Sorter.Backend = .claudeCode
    /// URLs marked to close on the iPhone. Written to iCloud Drive/Sift/close.txt.
    var closeQueue: [String] = []
    /// Opt-in: X post previews from X's unofficial syndication endpoint, which
    /// returns images. Off by default because the endpoint can stop working.
    var xSyndication: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SiftState()
        assignments = try c.decodeIfPresent([String: Assignment].self, forKey: .assignments) ?? [:]
        extraProjects = try c.decodeIfPresent([Project].self, forKey: .extraProjects) ?? []
        hiddenProjects = try c.decodeIfPresent([String].self, forKey: .hiddenProjects) ?? []
        projectsRoot = try c.decodeIfPresent(String.self, forKey: .projectsRoot) ?? defaults.projectsRoot
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID)
        backend = try c.decodeIfPresent(Sorter.Backend.self, forKey: .backend) ?? .claudeCode
        closeQueue = try c.decodeIfPresent([String].self, forKey: .closeQueue) ?? []
        xSyndication = try c.decodeIfPresent(Bool.self, forKey: .xSyndication) ?? false
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
