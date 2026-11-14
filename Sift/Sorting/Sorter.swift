import Foundation

/// Sorts tabs into projects with Claude, one batch per request.
/// Swift has no official Anthropic SDK, so this calls the Messages API over HTTP.
struct Sorter: Sendable {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Result: Decodable, Sendable {
        let id: Int
        let project: String
        let use: String
    }

    let apiKey: String
    var model = "claude-opus-5-5"
    static let batchSize = 40

    func sort(_ tabs: [SafariTab], projects: [Project]) async throws -> [String: Assignment] {
        let names = projects.map(\.name) + Project.buckets
        let catalogue = projects.map { "- \($0.name): \($0.summary.isEmpty ? "(no description)" : $0.summary)" }
            .joined(separator: "\n")
        let list = tabs.enumerated().map { index, tab in
            "\(index)\t\(tab.hasUsefulTitle ? tab.title : "(no title)")\t\(tab.url)"
        }.joined(separator: "\n")

        let system = """
            You sort a person's open browser tabs into the projects they work on. \
            Each tab is a link they kept open because it might be useful for one project.

            Projects:
            \(catalogue)

            Buckets that are not projects:
            - personal: the person's own life (shopping, travel, recipes they did not save for a project, news, entertainment).
            - drop: no lasting value (home pages, search pages, engagement bait, viral claims).
            - unknown: the title and URL do not say what the page is.

            For each tab, choose exactly one project or bucket. Choose a project only when the link could \
            feed that project's work. For a project, write "use": one short sentence on how the link could \
            be used in that project (a competitor, a reference, a data source, an argument, a feature idea). \
            For a bucket, leave "use" empty.
            """

        let schema: [String: Any] = [
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

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            // Server-side fallback: a refusal re-runs on a fallback model in the same call.
            "fallbacks": "default",
            "messages": [["role": "user", "content": "Tabs (id, title, URL):\n\(list)"]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "The API returned no JSON (HTTP \(status)).")
        }
        guard status == 200 else {
            let detail = ((json["error"] as? [String: Any])?["message"] as? String) ?? "unknown error"
            throw Failure(message: status == 401 ? "The API key was rejected. Check it in Settings." : "API error \(status): \(detail)")
        }
        switch json["stop_reason"] as? String {
        case "refusal": throw Failure(message: "Claude declined this batch.")
        case "max_tokens": throw Failure(message: "The answer was cut off. Try again.")
        default: break
        }

        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        struct Envelope: Decodable { let items: [Result] }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)) else {
            throw Failure(message: "Claude's answer did not match the expected format.")
        }

        var out: [String: Assignment] = [:]
        let valid = Set(names)
        for item in envelope.items where tabs.indices.contains(item.id) && valid.contains(item.project) {
            let isBucket = Project.buckets.contains(item.project)
            out[tabs[item.id].url] = Assignment(project: item.project, use: isBucket ? "" : item.use, manual: false)
        }
        return out
    }
}
