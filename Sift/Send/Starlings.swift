import AppKit
import CryptoKit
import Foundation

/// Sift as a Starlings MCP client. Starlings has no API keys: Sift signs in
/// like Claude Code does, with OAuth 2.1 (dynamic client registration, PKCE,
/// a loopback redirect), and calls tools with JSON-RPC over POST <origin>/mcp.
/// One sign-in per workspace; the tokens live in the login keychain. The
/// member can pause or revoke Sift in Starlings at any time.
enum Starlings {
    static let port: UInt16 = 53683
    static let redirectURI = "http://127.0.0.1:53683/callback"

    /// What the keychain keeps for one workspace.
    struct Session: Codable, Sendable {
        var clientID: String
        var access: String
        var refresh: String?
        var expires: Date
        var tokenEndpoint: String
    }

    /// "bipe", "bipe.starlings.work" or a full address, as https://host. A
    /// bare name is a workspace on starlings.work.
    static func origin(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        if !t.contains("."), !t.contains("/") { t += ".starlings.work" }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), u.scheme == "https", let host = u.host(), host.contains(".") else { return nil }
        return "https://\(host.lowercased())"
    }

    private static func service(_ origin: String) -> String { "app.sift.starlings." + (URL(string: origin)?.host() ?? origin) }

    static func load(_ origin: String) -> Session? {
        guard let s = Keychain.read(service: service(origin)), !s.isEmpty else { return nil }
        return try? JSONDecoder().decode(Session.self, from: Data(s.utf8))
    }

    static func store(_ session: Session?, for origin: String) {
        let text = session.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        _ = Keychain.save(text, service: service(origin))
    }

    // MARK: Sign-in

    /// Registers Sift with the workspace, opens the consent page in the
    /// browser and waits for the loopback callback.
    static func signIn(origin: String) async throws {
        let meta = try await json(URL(string: origin + "/.well-known/oauth-authorization-server")!)
        guard let authorize = meta["authorization_endpoint"] as? String,
              let tokenEndpoint = meta["token_endpoint"] as? String,
              let register = meta["registration_endpoint"] as? String
        else { throw SendFailure(message: "\(origin) does not look like a Starlings workspace.") }

        let registration = try await json(URL(string: register)!, body: [
            "client_name": "Sift",
            "redirect_uris": [redirectURI],
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "scope": "read write",
        ])
        guard let clientID = registration["client_id"] as? String else { throw SendFailure(message: "Starlings did not register Sift.") }

        let verifier = XAuth.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = XAuth.randomString(24)
        var c = URLComponents(string: authorize)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: "read write"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "resource", value: origin + "/mcp"),
        ]
        let callback = LoopbackServer(port: port, service: "Starlings")
        try callback.start()
        await MainActor.run { _ = NSWorkspace.shared.open(c.url!) }
        let query = try await callback.waitForQuery(timeout: 300)
        guard query["state"] == state else { throw SendFailure(message: "The sign-in answer did not match. Try again.") }
        if let error = query["error"] { throw SendFailure(message: "Starlings said: \(error)") }
        guard let code = query["code"] else { throw SendFailure(message: "Starlings sent no sign-in code.") }
        let session = try await token(tokenEndpoint, clientID: clientID, form: [
            "grant_type": "authorization_code", "code": code, "client_id": clientID,
            "redirect_uri": redirectURI, "code_verifier": verifier, "resource": origin + "/mcp",
        ], previousRefresh: nil)
        store(session, for: origin)
    }

    private static func token(_ endpoint: String, clientID: String, form: [String: String], previousRefresh: String?) async throws -> Session {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = answer["access_token"] as? String else {
            let detail = answer["error_description"] as? String ?? answer["error"] as? String ?? "unknown error"
            throw SendFailure(message: "Starlings sign-in failed: \(detail)")
        }
        return Session(clientID: clientID, access: access, refresh: answer["refresh_token"] as? String ?? previousRefresh,
                       expires: Date().addingTimeInterval(answer["expires_in"] as? Double ?? 3600), tokenEndpoint: endpoint)
    }

    /// A valid access token, refreshed when it is about to expire. Refresh
    /// tokens rotate, so the new one is stored every time.
    private static func access(_ origin: String, force: Bool = false) async throws -> String {
        guard var s = load(origin) else { throw SendFailure(message: "Connect \(origin) in Settings > Outputs first.") }
        if !force, s.expires.timeIntervalSinceNow > 60 { return s.access }
        guard let refresh = s.refresh else { throw SendFailure(message: "The Starlings sign-in expired. Connect again in Settings.") }
        s = try await token(s.tokenEndpoint, clientID: s.clientID, form: [
            "grant_type": "refresh_token", "refresh_token": refresh, "client_id": s.clientID, "resource": origin + "/mcp",
        ], previousRefresh: refresh)
        store(s, for: origin)
        return s.access
    }

    // MARK: Tools

    /// Calls one MCP tool and returns its structured answer (or the text,
    /// parsed as JSON when it is JSON).
    static func call(_ origin: String, tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        let result = try await rpc(origin, method: "tools/call", params: ["name": tool, "arguments": arguments])
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        if result["isError"] as? Bool == true { throw SendFailure(message: text.isEmpty ? "Starlings refused the call." : text) }
        if let structured = result["structuredContent"] as? [String: Any] { return structured }
        return ((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]) ?? ["text": text]
    }

    /// Reads one MCP resource as JSON.
    static func resource(_ origin: String, uri: String) async throws -> [String: Any] {
        let result = try await rpc(origin, method: "resources/read", params: ["uri": uri])
        let text = ((result["contents"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return ((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]) ?? [:]
    }

    /// One JSON-RPC request; a 401 refreshes the token and tries once more.
    private static func rpc(_ origin: String, method: String, params: [String: Any]) async throws -> [String: Any] {
        var retried = false
        while true {
            let token = try await access(origin, force: retried)
            var request = URLRequest(url: URL(string: origin + "/mcp")!, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, !retried { retried = true; continue }
            guard status == 200 else { throw SendFailure(message: "Starlings answered \(status).") }
            let message = try decodeMessage(data, contentType: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "")
            if let error = message["error"] as? [String: Any] {
                throw SendFailure(message: error["message"] as? String ?? "Starlings refused the call.")
            }
            return message["result"] as? [String: Any] ?? [:]
        }
    }

    /// A plain JSON answer, or the last `data:` event of a stream.
    private static func decodeMessage(_ data: Data, contentType: String) throws -> [String: Any] {
        var payload = data
        if contentType.contains("event-stream") {
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            if let last = lines.last(where: { $0.hasPrefix("data:") }) {
                payload = Data(last.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
            }
        }
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw SendFailure(message: "Starlings sent an answer Sift cannot read.")
        }
        return object
    }

    /// The workspace's own name, from its public descriptor
    /// (`/.well-known/meet`, field `name`). The host's first label when the
    /// descriptor cannot be read.
    static func workspaceName(_ origin: String) async -> String {
        if let url = URL(string: origin + "/.well-known/meet"),
           let answer = try? await json(url), let name = answer["name"] as? String, !name.isEmpty {
            return name
        }
        let label = URL(string: origin)?.host()?.split(separator: ".").first.map(String.init) ?? origin
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    /// The one destination per workspace: your link saves in its Docs.
    static func destination(for origin: String) async -> Destination {
        Destination(kind: "starlings", name: "Starlings: \(await workspaceName(origin))",
                    detail: URL(string: origin)?.host() ?? origin, config: ["origin": origin])
    }

    private static func json(_ url: URL, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SendFailure(message: "\(url.host() ?? "The workspace") did not answer as expected.") }
        return object
    }
}

/// Files a link as a Docs link save (a document with `source_kind` link,
/// listed under Links in Starlings Docs), private to you. Sift does not file
/// on projects (owner's call, 2026-11-14).
/// Starlings reads
/// the page itself, files it under /work/links, posts a line on the
/// project's channel, and answers the earlier save when the URL came before.
struct StarlingsSender: Sender {
    let kind = "starlings"
    let label = "Starlings"
    let symbol = "starlings"

    func send(_ item: SendItem, to destination: Destination) async throws -> String? {
        guard let origin = destination.config["origin"] else {
            throw SendFailure(message: "This Starlings destination is missing its workspace.")
        }
        var body: [String] = []
        if !item.note.isEmpty { body += [item.note, ""] }
        if !item.summary.isEmpty { body += [item.summary, ""] }
        body.append("Saved with Sift" + (item.theme.isEmpty ? "" : " · theme: \(item.theme)") + " · from \(item.source)")
        let key = SHA256.hash(data: Data("\(origin)||\(item.url)".utf8)).map { String(format: "%02x", $0) }.joined().prefix(64)
        var arguments: [String: Any] = [
            "url": item.url,
            "body_md": body.joined(separator: "\n"),
            "tags": ["sift"],
            "idempotency_key": String(key),
        ]
        let answer = try await Starlings.call(origin, tool: "docs_write", arguments: arguments)
        // The answer names the document; keep a web address when there is one.
        for k in ["url", "web_url", "share_url"] {
            if let s = answer[k] as? String, s.hasPrefix("http") { return s }
        }
        if let doc = answer["document"] as? [String: Any] {
            for k in ["url", "web_url"] { if let s = doc[k] as? String, s.hasPrefix("http") { return s } }
            if let id = doc["id"] as? String { return "document:\(id)" }
        }
        return (answer["door"] as? String) ?? (answer["id"] as? String).map { "document:\($0)" }
    }
}
