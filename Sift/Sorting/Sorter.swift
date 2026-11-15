import Foundation

/// Sorts tabs into projects with Claude, one batch per call.
///
/// Two backends share one prompt and one JSON schema:
/// - `.claudeCode` runs `claude -p` with the user's Claude Code login (no API key).
/// - `.api` calls the Messages API over HTTP with a key from the keychain
///   (Swift has no official Anthropic SDK).
struct Sorter: Sendable {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Backend: String, Codable, CaseIterable, Sendable {
        case claudeCode
        case api

        var label: String {
            switch self {
            case .claudeCode: "Claude Code (claude -p)"
            case .api: "Anthropic API key"
            }
        }
    }

    struct Result: Decodable, Sendable {
        let id: Int
        let project: String
        /// No longer requested (the owner removed use lines, 2026-11-14).
        let use: String?
    }

    /// One tab as the sorter sees it: title, URL and any preview text.
    struct Item: Sendable {
        let url: String
        let title: String
        let preview: String
    }

    let backend: Backend
    static let batchSize = 40

    func sort(_ items: [Item], projects: [Project]) async throws -> [String: Assignment] {
        let names = projects.map(\.name) + Project.buckets
        let system = Self.systemPrompt(projects: projects)
        let user = "Tabs (id, title, URL, preview):\n" + items.enumerated().map { index, item in
            let preview = item.preview.isEmpty ? "" : "\t\(item.preview.prefix(280))"
            return "\(index)\t\(item.title.isEmpty ? "(no title)" : item.title)\t\(item.url)\(preview)"
        }.joined(separator: "\n")
        let schema = Self.schema(names: names)

        let results = try await Self.ask(backend: backend, system: system, user: user, schema: schema, as: Envelope.self).items

        var out: [String: Assignment] = [:]
        let valid = Set(names)
        for r in results where items.indices.contains(r.id) && valid.contains(r.project) {
            out[items[r.id].url] = Assignment(project: r.project, use: "", manual: false, action: nil, sortedBy: "claude")
        }
        return out
    }

    /// One theme Claude found in the corpus.
    struct ThemeProposal: Decodable, Identifiable, Sendable {
        var id: String { name }
        var name: String
        var description: String
        var kind: String
        var destination: String
        var why: String
        /// The earlier theme this one continues, or "".
        var continues: String?
        var itemIDs: [Int]

        enum CodingKeys: String, CodingKey {
            case name, description, kind, why, continues
            case destination = "suggested_destination"
            case itemIDs = "item_ids"
        }
    }

    /// Finds themes bottom-up in the whole corpus, in one call, so the themes
    /// are consistent with each other. Destinations are only suggestions.
    func discoverThemes(_ items: [Item], destinations: [Project], keep: [Project]) async throws -> [ThemeProposal] {
        let places = destinations.map { "\($0.name)\($0.summary.isEmpty ? "" : " (\($0.summary.prefix(90)))")" }
            .joined(separator: "; ")
        let keepLine = keep.isEmpty ? "" : """

            The person already uses these themes. Keep their names where they still fit, and add, split or \
            drop themes only where the links call for it. When a new theme continues an old one (renamed, \
            merged or split), name the old one in "continues". The themes, with the person's own notes:
            \(keep.map { "- \($0.name): \($0.summary)\($0.notes.isEmpty ? "" : " Their note: \($0.notes)")" }.joined(separator: "\n"))
            """
        let system = """
            You find the themes in one person's saved links: open browser tabs and their reading list. Work \
            bottom-up from the links themselves, not from any project list. A theme is a sustained interest or \
            line of inquiry that several links feed, named the way the person would title it: short, \
            concrete, in Title Case (capitalize the main words, keep "and", "of", "on", "for", "the" lowercase, \
            write proper nouns and acronyms as they are written, for example AI, WhatsApp, Brazil). Aim for 12 to 20 themes. Prefer themes that cut \
            across tools and sources over themes that copy a product name. Put links with no lasting value \
            (viral bait, home pages, one-off curiosities) in one theme named "noise" with kind noise. Put \
            transactional pages, open for a task and not out of curiosity (orders, accounts, carts, listings \
            being compared, bookings, searches, dashboards, documents being edited), in one theme named \
            "errands" with kind errand. Put the person's private life interests that are not work or a hobby \
            (housing, travel, TV) in one theme named "personal" with kind personal. Every id goes in exactly \
            one theme.\(keepLine)

            For each theme give a one-sentence description of the interest, a kind (work, research, personal, \
            hobby, noise), a suggested_destination (the best existing home from the list below, several joined \
            with " + ", or "none yet") and a short "why" for it.

            Existing homes: \(places.isEmpty ? "none listed; suggest the kind of home that would fit, for example a project, a reading list or nowhere yet" : places)
            """
        let user = "Links (id, site, title, text):\n" + items.enumerated().map { index, item in
            let host = URL(string: item.url)?.host() ?? ""
            return "\(index)\t\(host)\t\(item.title.isEmpty ? "(no title)" : item.title.prefix(120))\t\(item.preview.prefix(180))"
                .replacingOccurrences(of: "\n", with: " ")
        }.joined(separator: "\n")
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["themes"],
            "properties": ["themes": ["type": "array", "items": [
                "type": "object", "additionalProperties": false,
                "required": ["name", "description", "kind", "suggested_destination", "why", "continues", "item_ids"],
                "properties": [
                    "name": ["type": "string"], "description": ["type": "string"],
                    "kind": ["type": "string", "enum": ["work", "research", "personal", "hobby", "noise", "errand"]],
                    "suggested_destination": ["type": "string"], "why": ["type": "string"],
                    "continues": ["type": "string"],
                    "item_ids": ["type": "array", "items": ["type": "integer"]],
                ],
            ]]],
        ]
        struct Themes: Decodable { let themes: [ThemeProposal] }
        return try await Self.ask(backend: backend, system: system, user: user, schema: schema, as: Themes.self).themes
    }

    /// Which other themes each link also feeds, beyond the one it is in.
    /// Most links feed one theme; the answer lists only clear second uses.
    func connections(_ items: [(item: Item, theme: String)], themes: [Project]) async throws -> [Int: [String]] {
        let names = themes.map(\.name)
        let system = """
            A person's saved links are sorted into themes, one theme each. Some links also clearly feed a \
            second or third theme: a post about AI in Brazilian schools feeds both an AI theme and an \
            education theme. For each link, list the OTHER themes it clearly feeds, at most two. Most links \
            feed only their own theme: give them an empty list. Do not repeat the link's own theme.

            Themes:
            \(themes.map { "- \($0.name): \($0.summary)" }.joined(separator: "\n"))
            """
        let user = "Links (id, theme, site, title, text):\n" + items.enumerated().map { index, pair in
            let host = URL(string: pair.item.url)?.host() ?? ""
            return "\(index)\t\(pair.theme)\t\(host)\t\(pair.item.title.prefix(120))\t\(pair.item.preview.prefix(160))"
                .replacingOccurrences(of: "\n", with: " ")
        }.joined(separator: "\n")
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["links"],
            "properties": ["links": ["type": "array", "items": [
                "type": "object", "additionalProperties": false, "required": ["id", "also"],
                "properties": [
                    "id": ["type": "integer"],
                    "also": ["type": "array", "items": ["type": "string", "enum": names]],
                ],
            ]]],
        ]
        struct Answer: Decodable { struct Link: Decodable { let id: Int; let also: [String] }; let links: [Link] }
        let answer = try await Self.ask(backend: backend, system: system, user: user, schema: schema, as: Answer.self)
        var result: [Int: [String]] = [:]
        for l in answer.links where items.indices.contains(l.id) {
            result[l.id] = Array(l.also.filter { names.contains($0) && $0 != items[l.id].theme }.prefix(2))
        }
        return result
    }

    static func ask<T: Decodable>(backend: Backend, system: String, user: String, schema: [String: Any], as: T.Type) async throws -> T {
        let data: Data
        switch backend {
        case .claudeCode: data = try await ClaudeCodeRunner.run(system: system, user: user, schema: schema)
        case .api:
            guard let key = Keychain.readKey() else { throw Failure(message: "Add an Anthropic API key in Settings, or switch to Claude Code.") }
            data = try await APIRunner.run(key: key, system: system, user: user, schema: schema)
        }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw Failure(message: "Claude's answer did not match the expected format.")
        }
        return value
    }

    static func systemPrompt(projects: [Project]) -> String {
        let catalogue = projects.map { "- \($0.name): \($0.summary.isEmpty ? "(no description)" : $0.summary)\($0.notes.isEmpty ? "" : " Owner's note: \($0.notes)")" }
            .joined(separator: "\n")
        return """
            You sort a person's open browser tabs into their projects or themes. \
            Each tab is a link they kept open because it might be useful for one of them.

            Projects or themes:
            \(catalogue)

            Buckets that are not projects:
            - errands: transactional pages, open for a task and not out of curiosity (orders, accounts, carts, \
              listings being compared, bookings, searches, dashboards, documents being edited).
            - personal: the person's own life (travel, recipes, news, entertainment).
            - drop: no lasting value (home pages, search pages, engagement bait, viral claims).
            - unknown: the title, URL and preview do not say what the page is.

            For each tab, choose exactly one project or bucket. Choose a project only when the link could \
            feed that project's work. Return every id.
            """
    }

    static func schema(names: [String]) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["items"],
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["id", "project"],
                        "properties": [
                            "id": ["type": "integer"],
                            "project": ["type": "string", "enum": names],
                        ],
                    ],
                ],
            ],
        ]
    }

    fileprivate struct Envelope: Decodable { let items: [Result] }
}

/// Runs `claude -p` headless. Tools, MCP servers, skills, settings and the
/// default system prompt are all off, so one call costs about the size of the
/// tab list. `--bare` is not used: it skips the stored login.
enum ClaudeCodeRunner {
    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appending(path: ".local/bin/claude"),
            home.appending(path: ".claude/local/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    /// Shown when Claude Code has no stored login or its login expired.
    static let loginMessage = "Claude Code is not signed in on this Mac. Open Terminal, type claude and press Return, then type /login and follow the steps in your browser. Then try again in Sift. You can also use an Anthropic API key, in Settings > Intelligence."

    /// True when Claude Code's error text says it needs a login
    /// ("Not logged in · Please run /login", an expired or revoked token).
    static func needsLogin(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("not logged in") || t.contains("/login") || t.contains("invalid api key")
            || t.contains("oauth token") || t.contains("authentication_error")
    }

    /// Returns the structured output as JSON data.
    static func run(system: String, user: String, schema: [String: Any]) async throws -> Data {
        guard let exe = executable else {
            throw Sorter.Failure(message: "Claude Code was not found. Install it, or switch to an API key in Settings.")
        }
        let schemaJSON = String(decoding: try JSONSerialization.data(withJSONObject: schema), as: UTF8.self)
        let args = [
            "-p", "--output-format", "json",
            "--json-schema", schemaJSON,
            "--model", "opus",
            "--tools", "",
            "--system-prompt", system,
            "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
            "--setting-sources", "",
            "--disable-slash-commands",
            "--no-session-persistence",
        ]
        let output = try await Self.launch(exe, args: args, stdin: user)
        guard let json = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            throw Sorter.Failure(message: "Claude Code returned no JSON.")
        }
        if json["is_error"] as? Bool == true {
            let message = json["result"] as? String ?? "unknown error"
            throw Sorter.Failure(message: Self.needsLogin(message) ? Self.loginMessage : "Claude Code: \(message)")
        }
        guard let structured = json["structured_output"],
              let data = try? JSONSerialization.data(withJSONObject: structured)
        else { throw Sorter.Failure(message: "Claude Code's answer did not match the expected format.") }
        return data
    }

    private static func launch(_ exe: URL, args: [String], stdin: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = exe
            process.arguments = args
            // Run outside any project so no project CLAUDE.md loads.
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (env["PATH"].map { $0 + ":" } ?? "") + "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = env
            let input = Pipe(), out = Pipe(), err = Pipe()
            process.standardInput = input
            process.standardOutput = out
            process.standardError = err
            // Read stdout on a background queue so a full pipe cannot block the child.
            let collector = DataCollector()
            out.fileHandleForReading.readabilityHandler = { handle in collector.append(handle.availableData) }
            process.terminationHandler = { p in
                out.fileHandleForReading.readabilityHandler = nil
                collector.append(out.fileHandleForReading.readDataToEndOfFile())
                let data = collector.data
                if p.terminationStatus == 0 || !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    if Self.needsLogin(message) {
                        continuation.resume(throwing: Sorter.Failure(message: Self.loginMessage))
                        return
                    }
                    continuation.resume(throwing: Sorter.Failure(message: "Claude Code exited with \(p.terminationStatus). \(message.prefix(300))"))
                }
            }
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(stdin.utf8))
                try? input.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    func append(_ d: Data) { lock.lock(); buffer.append(d); lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
}

/// Messages API over HTTP. Model claude-opus-5-5, low effort, structured
/// output, server-side fallback on refusal.
enum APIRunner {
    /// Returns the structured output as JSON data.
    static func run(key: String, system: String, user: String, schema: [String: Any]) async throws -> Data {
        let body: [String: Any] = [
            "model": "claude-opus-5-5",
            "max_tokens": 16000,
            "system": system,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "fallbacks": "default",
            "messages": [["role": "user", "content": user]],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Sorter.Failure(message: "The API returned no JSON (HTTP \(status)).")
        }
        guard status == 200 else {
            let detail = ((json["error"] as? [String: Any])?["message"] as? String) ?? "unknown error"
            throw Sorter.Failure(message: status == 401 ? "The API key was rejected. Check it in Settings." : "API error \(status): \(detail)")
        }
        switch json["stop_reason"] as? String {
        case "refusal": throw Sorter.Failure(message: "Claude declined this batch.")
        case "max_tokens": throw Sorter.Failure(message: "The answer was cut off. Try again.")
        default: break
        }
        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return Data(text.utf8)
    }
}
