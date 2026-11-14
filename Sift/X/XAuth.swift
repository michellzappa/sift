import AppKit
import CryptoKit
import Foundation
import Network

/// Signs in to X with OAuth 2.0 Authorization Code + PKCE as a native
/// (public) client: no client secret. The browser comes back to a one-shot
/// loopback server on 127.0.0.1. Tokens go to the login keychain.
///
/// The user registers their own X app in the X Developer Console (type
/// "Native App") with the callback URL `XAuth.redirectURI`, and pastes its
/// Client ID into Sift's settings.
enum XAuth {
    static let port: UInt16 = 53682
    static let redirectURI = "http://127.0.0.1:53682/callback"
    static let scopes = "tweet.read users.read bookmark.read offline.access"

    struct Tokens: Codable, Sendable {
        var access: String
        var refresh: String?
        var expires: Date
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func load() -> Tokens? {
        guard let s = Keychain.read(service: Keychain.xTokensService) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: Data(s.utf8))
    }

    static func store(_ t: Tokens?) {
        guard let t, let data = try? JSONEncoder().encode(t) else {
            Keychain.save("", service: Keychain.xTokensService)
            return
        }
        Keychain.save(String(decoding: data, as: UTF8.self), service: Keychain.xTokensService)
    }

    /// Opens the browser, waits for the callback and exchanges the code.
    static func signIn(clientID: String) async throws -> Tokens {
        let verifier = randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomString(24)
        var c = URLComponents(string: "https://x.com/i/oauth2/authorize")!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        let callback = LoopbackServer(port: port)
        try callback.start()
        await MainActor.run { _ = NSWorkspace.shared.open(c.url!) }
        let query = try await callback.waitForQuery(timeout: 300)
        guard query["state"] == state else { throw Failure(message: "The sign-in answer did not match. Try again.") }
        if let error = query["error"] { throw Failure(message: "X said: \(error)") }
        guard let code = query["code"] else { throw Failure(message: "X sent no sign-in code.") }
        let tokens = try await token(form: [
            "grant_type": "authorization_code", "code": code, "client_id": clientID,
            "redirect_uri": redirectURI, "code_verifier": verifier,
        ])
        store(tokens)
        return tokens
    }

    /// A valid access token, refreshed when it is about to expire.
    static func accessToken(clientID: String) async throws -> String {
        guard var t = load() else { throw Failure(message: "Connect your X account in Settings first.") }
        if t.expires.timeIntervalSinceNow > 60 { return t.access }
        guard let refresh = t.refresh else { throw Failure(message: "The X sign-in expired. Connect again in Settings.") }
        t = try await token(form: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID])
        store(t)
        return t.access
    }

    private static func token(form: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://api.x.com/2/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else {
            let detail = json["error_description"] as? String ?? json["error"] as? String ?? "unknown error"
            throw Failure(message: "X sign-in failed: \(detail)")
        }
        let seconds = json["expires_in"] as? Double ?? 7200
        let refresh = json["refresh_token"] as? String ?? (form["refresh_token"])
        return Tokens(access: access, refresh: refresh, expires: Date().addingTimeInterval(seconds))
    }

    private static func randomString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URL.prefix(length).description
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// A one-shot HTTP server on 127.0.0.1 that hands back the query string of
/// the first request and answers with a short "you can close this tab" page.
final class LoopbackServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: NWListener?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var result: Result<[String: String], Error>?

    init(port: UInt16) { self.port = port }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.finish(.failure(error)) }
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    func waitForQuery(timeout: TimeInterval) async throws -> [String: String] {
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(XAuth.Failure(message: "Sign-in timed out.")))
        }
        return try await withCheckedThrowingContinuation { c in
            lock.lock()
            if let result { lock.unlock(); c.resume(with: result); return }
            continuation = c
            lock.unlock()
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let line = request.split(separator: "\r\n").first.map(String.init) ?? ""
            let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            var query: [String: String] = [:]
            for item in URLComponents(string: "http://127.0.0.1" + path)?.queryItems ?? [] { query[item.name] = item.value ?? "" }
            let page = "<html><body style=\"font: 15px -apple-system; padding: 40px\"><h3>Sift is connected to X.</h3><p>You can close this tab.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if !query.isEmpty { self?.finish(.success(query)) }
        }
    }

    private func finish(_ value: Result<[String: String], Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let c = continuation
        continuation = nil
        lock.unlock()
        listener?.cancel()
        c?.resume(with: value)
    }
}
