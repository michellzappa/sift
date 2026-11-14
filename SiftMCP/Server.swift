import Foundation

/// Writes protocol messages to stdout, one JSON object per line.
enum Output {
    static func send(_ message: Any) {
        guard JSONSerialization.isValidJSONObject(message),
              var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
        else {
            Log.write("could not encode a reply")
            return
        }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

/// Diagnostics go to stderr; the MCP client shows or stores them as logs.
enum Log {
    static func write(_ text: String) {
        FileHandle.standardError.write(Data("[sift-mcp] \(text)\n".utf8))
    }
}

/// JSON-RPC 2.0 dispatch for the MCP methods Sift supports.
struct MCPServer {
    let version: String

    static let supportedProtocols = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// The version of the enclosing Sift.app (Contents/Info.plist), or "dev"
    /// when the tool runs outside the app.
    static func appVersion() -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return value
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath()
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOf: plist),
           let value = info["CFBundleShortVersionString"] as? String {
            return value
        }
        return "dev"
    }

    /// Handles one line from stdin. Returns the reply, or nil for
    /// notifications and for batches that only held notifications.
    func handle(line: String) -> Any? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
            return Self.error(id: NSNull(), code: -32700, message: "Parse error")
        }
        if let batch = json as? [Any] {
            if batch.isEmpty { return Self.error(id: NSNull(), code: -32600, message: "Invalid Request") }
            let replies = batch.compactMap { handle(message: $0) }
            return replies.isEmpty ? nil : replies
        }
        return handle(message: json)
    }

    private func handle(message: Any) -> [String: Any]? {
        guard let request = message as? [String: Any], let method = request["method"] as? String else {
            // A response from the client (we send no requests) or garbage.
            if let object = message as? [String: Any], object["result"] != nil || object["error"] != nil {
                return nil
            }
            return Self.error(id: NSNull(), code: -32600, message: "Invalid Request")
        }
        let params = request["params"] as? [String: Any] ?? [:]
        guard let id = request["id"], !(id is NSNull) else {
            // Notifications (notifications/initialized, cancelled, ...) get no reply.
            return nil
        }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let chosen = Self.supportedProtocols.contains(asked) ? asked : Self.supportedProtocols[0]
            return Self.result(id: id, [
                "protocolVersion": chosen,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "sift", "version": version],
                "instructions": Tools.instructions,
            ])
        case "ping":
            return Self.result(id: id, [String: Any]())
        case "tools/list":
            return Self.result(id: id, ["tools": Tools.definitions])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.error(id: id, code: -32602, message: "Missing tool name")
            }
            guard Tools.names.contains(name) else {
                return Self.error(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let outcome = Tools.call(name, arguments: arguments)
            var result: [String: Any] = ["content": [["type": "text", "text": outcome.text]]]
            if outcome.isError { result["isError"] = true }
            return Self.result(id: id, result)
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
}
