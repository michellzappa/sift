import AppKit
import Foundation

/// The tools that change Sift or read what only the app knows (issue #34).
/// Each call drops a request for the running app (Shared/AgentRequests.swift)
/// and waits for its result. This server never writes Sift's state.
enum AgentCalls {
    static let names: Set<String> = Set(AgentTools.writes + AgentTools.reads + AgentTools.local)

    private static func tool(_ name: String, _ title: String, _ description: String,
                             _ properties: [String: [String: Any]] = [:], required: [String] = []) -> [String: Any] {
        ["name": name, "title": title, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }
    private static func text(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func list(_ d: String) -> [String: Any] { ["type": "array", "items": ["type": "string"], "description": d] }

    static var definitions: [[String: Any]] {
        [
            tool("merge_themes", "Merge two themes", "Moves every link, note and history line of theme `from` into theme `into`, and removes `from`. Cannot be undone except by moving links by hand.",
                 ["from": text("Theme to remove (from list_themes)."), "into": text("Theme that stays.")], required: ["from", "into"]),
            tool("rename_theme", "Rename a theme", "Renames a theme. Links, notes and history stay with it.",
                 ["name": text("Current theme name."), "to": text("New name.")], required: ["name", "to"]),
            tool("move_link", "Move a link to a theme", "Files one link under a theme (or the drop, personal or errands bucket). Counts as a hand move: sorting never overrides it.",
                 ["url": text("The link's URL."), "theme": text("Theme name, or drop, personal or errands.")], required: ["url", "theme"]),
            tool("add_note", "Add a note to a link", "Saves the user's note on a link (searchable). Empty text removes the note.",
                 ["url": text("The link's URL."), "text": text("The note.")], required: ["url"]),
            tool("sort_unsorted", "Sort unsorted links", "Files every link that is in no theme into the existing themes, with the user's own Claude. A long job: returns a job id for job_status.", [:]),
            tool("propose_new_themes", "Propose themes for unsorted links", "Reads only the links in no theme and proposes new themes for those that fit none of the current themes; the current themes stay as they are. A long job: job_status returns the proposal with its id. Nothing changes until apply_theme_proposal.", [:]),
            tool("apply_theme_proposal", "Apply a theme proposal", "Adds the proposal's new themes and files its links. Current themes and hand moves are not touched.",
                 ["proposal": text("Proposal id from propose_new_themes."),
                  "accept": list("Names of the themes to apply (new and existing). Default: all."),
                  "rename": list("Renames for new themes, each as \"Old => New\".")], required: ["proposal"]),
            tool("follow", "Follow a feed", "Follows anything the Follow sheet takes: a site, a feed address, r/subreddit, @name.bsky.social, @user@instance, a YouTube channel, \"podcast: name\", \"news: words\".",
                 ["input": text("What to follow."), "folder": text("Optional folder."),
                  "priority": text("Optional place in Today: auto, must (Don't Miss), normal, best (Best Only) or off.")], required: ["input"]),
            tool("unfollow", "Unfollow a feed", "Stops following a feed and removes its items.",
                 ["feed": text("Feed title, address or id (from list_feeds).")], required: ["feed"]),
            tool("set_feed_priority", "Set a feed's place in Today", "auto, must (Don't Miss), normal, best (Best Only) or off (Not in Today).",
                 ["feed": text("Feed title, address or id."), "priority": text("auto, must, normal, best or off.")], required: ["feed", "priority"]),
            tool("move_feed", "Move a feed to a folder", "Puts a feed in a folder; leave folder out for no folder.",
                 ["feed": text("Feed title, address or id."), "folder": text("Folder name.")], required: ["feed"]),
            tool("check_feeds", "Check all feeds now", "Fetches every feed and updates Today. A long job: returns a job id.", [:]),
            tool("mark_seen", "Mark links seen or unseen", "Sets the seen mark on links (synced to the user's iPhone).",
                 ["urls": list("Link URLs."), "seen": ["type": "boolean", "description": "true for seen (default), false for unseen."]], required: ["urls"]),
            tool("keep", "Keep a Today item", "Moves a Today or feed item into the library, like Keep in the app.",
                 ["url": text("The item's URL (from today).")], required: ["url"]),
            tool("send", "Send a link to a destination", "Sends a link to one of the user's Send destinations (Starlings, Obsidian, Markdown, Reading List). This leaves the Mac: confirm with the user first.",
                 ["url": text("The link's URL."), "destination": text("Destination name from list_destinations.")], required: ["url", "destination"]),
            tool("list_feeds", "List followed feeds", "Every followed feed with its folder, place in Today, posting rate and what Sift learned from the user's reading.", [:]),
            tool("today", "Read Today", "Today's picks with the reason for each, seen or unseen, kept or not.", [:]),
            tool("unsorted", "List unsorted links", "Links in no theme.",
                 ["limit": ["type": "integer", "minimum": 1, "maximum": 500, "default": 50]]),
            tool("list_destinations", "List Send destinations", "The user's Send destinations, for send.", [:]),
            tool("job_status", "Check a job", "The result of a long job (sort_unsorted, propose_new_themes, check_feeds) or any earlier call, by its id.",
                 ["id": text("The id a call returned.")], required: ["id"]),
            tool("agent_log", "Recent agent actions", "The latest requests made through these tools and their outcome.",
                 ["limit": ["type": "integer", "minimum": 1, "maximum": 100, "default": 20]]),
        ]
    }

    static func call(_ name: String, arguments: [String: Any]) -> Tools.Outcome {
        switch name {
        case "job_status": return jobStatus(arguments["id"] as? String ?? "")
        case "agent_log": return log(limit: arguments["limit"] as? Int ?? 20)
        default: return request(name, arguments)
        }
    }

    // MARK: Requests

    private static func strings(_ value: Any) -> [String] {
        switch value {
        case let s as String: return [s]
        case let n as NSNumber: return [CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue]
        case let a as [Any]: return a.flatMap(strings)
        default: return []
        }
    }

    private static func request(_ tool: String, _ arguments: [String: Any]) -> Tools.Outcome {
        AgentFiles.prepare()
        let id = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8).lowercased())"
        let r = AgentRequest(id: id, tool: tool, args: arguments.mapValues(strings), at: Date())
        guard let data = try? AgentFiles.coder.0.encode(r),
              (try? data.write(to: AgentFiles.requests.appendingPathComponent("\(id).json"), options: .atomic)) != nil else {
            return Tools.Outcome(text: "Could not write the request.", isError: true)
        }
        var wait: TimeInterval = 20
        if NSRunningApplication.runningApplications(withBundleIdentifier: "app.sift.Sift").isEmpty {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-g", "-b", "app.sift.Sift"]
            try? open.run(); open.waitUntilExit()
            wait = 45
        }
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if let result = readResult(id) { return outcome(result) }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return Tools.Outcome(text: "Sift has not answered yet; the request is queued and runs when Sift is open. Its id is \(id): check it with job_status.")
    }

    private static func readResult(_ id: String) -> AgentResult? {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard let data = try? Data(contentsOf: AgentFiles.results.appendingPathComponent("\(safe).json")) else { return nil }
        return try? AgentFiles.coder.1.decode(AgentResult.self, from: data)
    }

    private static func outcome(_ r: AgentResult) -> Tools.Outcome {
        switch r.status {
        case "started": return Tools.Outcome(text: "\(r.text)\nJob id: \(r.id)")
        case "failed": return Tools.Outcome(text: r.text, isError: true)
        default: return Tools.Outcome(text: r.text)
        }
    }

    private static func jobStatus(_ id: String) -> Tools.Outcome {
        guard let r = readResult(id) else { return Tools.Outcome(text: "No result with id \(id) yet. Sift may not be open.") }
        if r.status == "started" { return Tools.Outcome(text: "Still running. \(r.text)") }
        return outcome(r)
    }

    private static func log(limit: Int) -> Tools.Outcome {
        guard let text = try? String(contentsOf: AgentFiles.log, encoding: .utf8) else {
            return Tools.Outcome(text: "No agent actions yet.")
        }
        let lines = text.split(separator: "\n").suffix(max(1, min(limit, 100)))
        return Tools.Outcome(text: lines.joined(separator: "\n"))
    }
}
