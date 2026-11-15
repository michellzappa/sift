import Foundation

// Agent requests (issue #34). sift-mcp never writes Sift's state: it drops a
// request in Application Support/Sift/agent/requests, the running app does
// the work through its normal save path and writes a result to
// agent/results. This file is compiled into both Sift and sift-mcp, so the
// two sides cannot drift.

enum AgentFiles {
    /// The real Sift folder. sift-mcp has no demo mode; the app refuses
    /// requests in demo mode.
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Sift", isDirectory: true)
    static let root = support.appendingPathComponent("agent", isDirectory: true)
    static let requests = root.appendingPathComponent("requests", isDirectory: true)
    static let results = root.appendingPathComponent("results", isDirectory: true)
    static let log = root.appendingPathComponent("log.jsonl")

    static func prepare() {
        for dir in [root, requests, results] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
    }

    static let coder: (JSONEncoder, JSONDecoder) = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }()
}

/// One request. Every argument is a list of strings; a single value is a
/// list of one.
struct AgentRequest: Codable, Sendable {
    var id: String
    var tool: String
    var args: [String: [String]]
    var at: Date

    func first(_ key: String) -> String? {
        args[key]?.first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }
    func list(_ key: String) -> [String] {
        (args[key] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

struct AgentResult: Codable, Sendable {
    /// done, failed, or started (a long job; job_status reads it later).
    var id: String
    var tool: String
    var status: String
    /// What the agent reads: what changed, or the data asked for.
    var text: String
    var at: Date
}

/// The tools the app runs. sift-mcp lists them; AppModel+Agent handles them.
enum AgentTools {
    /// Tools that change something.
    static let writes: [String] = [
        "merge_themes", "rename_theme", "move_link", "add_note",
        "sort_unsorted", "propose_new_themes", "apply_theme_proposal",
        "follow", "unfollow", "set_feed_priority", "move_feed", "check_feeds",
        "mark_seen", "keep", "send",
    ]
    /// Tools that read state only the app has (not in search.sqlite).
    static let reads: [String] = ["list_feeds", "today", "unsorted", "list_destinations"]
    /// Answered from agent/results by sift-mcp itself.
    static let local: [String] = ["job_status", "agent_log"]
}
