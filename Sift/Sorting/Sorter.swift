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
        let use: String
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

        let results: [Result]
        switch backend {
        case .claudeCode: results = try await ClaudeCodeRunner.run(system: system, user: user, schema: schema)
        case .api:
            guard let key = Keychain.readKey() else { throw Failure(message: "Add an Anthropic API key in Settings, or switch to Claude Code.") }
            results = try await APIRunner.run(key: key, system: system, user: user, schema: schema)
        }

        var out: [String: Assignment] = [:]
        let valid = Set(names)
        for r in results where items.indices.contains(r.id) && valid.contains(r.project) {
            let isBucket = Project.buckets.contains(r.project)
            out[items[r.id].url] = Assignment(project: r.project, use: isBucket ? "" : r.use, manual: false)
        }
        return out
    }

    static func systemPrompt(projects: [Project]) -> String {
        let catalogue = projects.map { "- \($0.name): \($0.summary.isEmpty ? "(no description)" : $0.summary)" }
            .joined(separator: "\n")
        return """
            You sort a person's open browser tabs into the projects they work on. \
            Each tab is a link they kept open because it might be useful for one project.

            Projects:
            \(catalogue)

            Buckets that are not projects:
            - personal: the person's own life (shopping, travel, recipes, news, entertainment).
            - drop: no lasting value (home pages, search pages, engagement bait, viral claims).
            - unknown: the title, URL and preview do not say what the page is.

            For each tab, choose exactly one project or bucket. Choose a project only when the link could \
            feed that project's work. For a project, write "use": one short sentence on how the link could \
            be used in that project (a competitor, a reference, a data source, an argument, a feature idea). \
            For a bucket, leave "use" empty. Return every id.
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
                        "required": ["id", "project", "use"],
                        "properties": [
                            "id": ["type": "integer"],
                            "project": ["type": "string", "enum": names],
                            "use": ["type": "string"],
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

    static func run(system: String, user: String, schema: [String: Any]) async throws -> [Sorter.Result] {
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
            throw Sorter.Failure(message: "Claude Code: \(message)")
        }
        guard let structured = json["structured_output"],
              let data = try? JSONSerialization.data(withJSONObject: structured),
              let envelope = try? JSONDecoder().decode(Sorter.Envelope.self, from: data)
        else { throw Sorter.Failure(message: "Claude Code's answer did not match the expected format.") }
        return envelope.items
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
    static func run(key: String, system: String, user: String, schema: [String: Any]) async throws -> [Sorter.Result] {
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
        guard let envelope = try? JSONDecoder().decode(Sorter.Envelope.self, from: Data(text.utf8)) else {
            throw Sorter.Failure(message: "Claude's answer did not match the expected format.")
        }
        return envelope.items
    }
}
