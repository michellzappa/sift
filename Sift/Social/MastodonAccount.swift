import AppKit
import CryptoKit
import Foundation

/// Sift's Mastodon sign-in, for light actions only: like (favourite) a post
/// and save it to the person's bookmarks. Sift registers itself as an app
/// on the person's instance (POST /api/v1/apps), then signs in with OAuth,
/// PKCE and a loopback redirect (`LoopbackServer`, shared with X and
/// Starlings). The token lives in the keychain per instance
/// (`app.sift.mastodon.<host>`); UserDefaults `social.mastodonInstance`
/// names the instance in use. Mastodon tokens do not expire; Sign Out
/// revokes the token.
enum MastodonAccount {
    static let port: UInt16 = 53684
    static let redirectURI = "http://127.0.0.1:53684/callback"
    /// Smallest set: the account name, search (to find a post from its
    /// link with resolve=true), favourites and bookmarks.
    static let scopes = "read:accounts read:search write:favourites write:bookmarks"
    static let instanceKey = "social.mastodonInstance"

    struct Session: Codable, Sendable {
        var instance: String
        var clientID: String
        var clientSecret: String
        var access: String
        var username: String
    }

    /// One post as the signed-in person sees it, by its id on their instance.
    struct StatusState: Sendable, Equatable {
        var id: String
        var favourited: Bool
        var bookmarked: Bool
    }

    private static func service(_ instance: String) -> String {
        "app.sift.mastodon." + (URL(string: instance)?.host() ?? instance)
    }

    static func load() -> Session? {
        guard let instance = UserDefaults.standard.string(forKey: instanceKey),
              let s = Keychain.read(service: service(instance)) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: Data(s.utf8))
    }

    /// "mastodon.social", "@me@mastodon.social" or a full address, as
    /// https://host.
    static func origin(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("@") { t.removeFirst() }
        if !t.contains("://"), let at = t.lastIndex(of: "@") { t = String(t[t.index(after: at)...]) }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), u.scheme == "https", let host = u.host(), host.contains(".") else { return nil }
        return "https://\(host.lowercased())"
    }

    // MARK: Sign-in

    static func signIn(_ text: String) async throws -> Session {
        guard !Demo.isOn else { throw SendFailure(message: Demo.offMessage) }
        guard let instance = origin(text) else { throw SendFailure(message: "Type your instance, for example mastodon.social.") }

        let (status, app) = try await send(instance + "/api/v1/apps", method: "POST", form: [
            "client_name": "Sift", "redirect_uris": redirectURI, "scopes": scopes,
        ])
        guard status == 200, let clientID = app["client_id"] as? String, let secret = app["client_secret"] as? String else {
            throw SendFailure(message: "\(instance) did not register Sift: \(detail(app, status))")
        }

        let verifier = XAuth.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = XAuth.randomString(24)
        var c = URLComponents(string: instance + "/oauth/authorize")!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        let callback = LoopbackServer(port: port, service: "Mastodon")
        try callback.start()
        await MainActor.run { _ = NSWorkspace.shared.open(c.url!) }
        let query = try await callback.waitForQuery(timeout: 300)
        guard query["state"] == state else { throw SendFailure(message: "The sign-in answer did not match. Try again.") }
        if let error = query["error"] { throw SendFailure(message: "Mastodon said: \(query["error_description"] ?? error)") }
        guard let code = query["code"] else { throw SendFailure(message: "Mastodon sent no sign-in code.") }

        let (tokenStatus, token) = try await send(instance + "/oauth/token", method: "POST", form: [
            "grant_type": "authorization_code", "code": code, "client_id": clientID, "client_secret": secret,
            "redirect_uri": redirectURI, "code_verifier": verifier, "scope": scopes,
        ])
        guard tokenStatus == 200, let access = token["access_token"] as? String else {
            throw SendFailure(message: "Mastodon sign-in failed: \(detail(token, tokenStatus))")
        }
        let (_, me) = try await send(instance + "/api/v1/accounts/verify_credentials", method: "GET", token: access)
        let host = URL(string: instance)?.host() ?? instance
        let session = Session(instance: instance, clientID: clientID, clientSecret: secret, access: access,
                              username: "\(me["username"] as? String ?? "you")@\(host)")
        guard let data = try? JSONEncoder().encode(session),
              Keychain.save(String(decoding: data, as: UTF8.self), service: service(instance))
        else { throw SendFailure(message: "Sift could not save the Mastodon sign-in in the keychain.") }
        UserDefaults.standard.set(instance, forKey: instanceKey)
        return session
    }

    static func signOut() async {
        if let s = load(), !Demo.isOn {
            _ = try? await send(s.instance + "/oauth/revoke", method: "POST", form: [
                "client_id": s.clientID, "client_secret": s.clientSecret, "token": s.access,
            ])
            Keychain.save("", service: service(s.instance))
        }
        UserDefaults.standard.removeObject(forKey: instanceKey)
    }

    // MARK: Light actions

    /// Finds the post behind a link on the person's own instance (search
    /// with resolve=true fetches a post from another server once).
    static func status(_ url: String) async throws -> StatusState {
        let s = try session()
        var c = URLComponents(string: s.instance + "/api/v2/search")!
        c.queryItems = [
            .init(name: "q", value: url), .init(name: "type", value: "statuses"),
            .init(name: "resolve", value: "true"), .init(name: "limit", value: "1"),
        ]
        let (status, answer) = try await send(c.url!.absoluteString, method: "GET", token: s.access)
        guard status == 200 else { throw SendFailure(message: "Mastodon said: \(detail(answer, status))") }
        guard let post = (answer["statuses"] as? [[String: Any]])?.first else {
            throw SendFailure(message: "Your instance could not find this post.")
        }
        return state(post) ?? StatusState(id: "", favourited: false, bookmarked: false)
    }

    static func setFavourite(_ on: Bool, _ post: StatusState) async throws -> StatusState {
        try await act(post, on ? "favourite" : "unfavourite")
    }

    static func setBookmark(_ on: Bool, _ post: StatusState) async throws -> StatusState {
        try await act(post, on ? "bookmark" : "unbookmark")
    }

    private static func act(_ post: StatusState, _ verb: String) async throws -> StatusState {
        let s = try session()
        guard !post.id.isEmpty else { throw SendFailure(message: "Your instance could not find this post.") }
        let (status, answer) = try await send(s.instance + "/api/v1/statuses/\(post.id)/\(verb)", method: "POST", token: s.access)
        guard status == 200, let next = state(answer) else { throw SendFailure(message: "Mastodon said: \(detail(answer, status))") }
        return next
    }

    private static func state(_ post: [String: Any]) -> StatusState? {
        guard let id = post["id"] as? String else { return nil }
        return StatusState(id: id, favourited: post["favourited"] as? Bool ?? false, bookmarked: post["bookmarked"] as? Bool ?? false)
    }

    private static func session() throws -> Session {
        guard !Demo.isOn else { throw SendFailure(message: Demo.offMessage) }
        guard let s = load() else { throw SendFailure(message: "Sign in to Mastodon in Settings > Inputs first.") }
        return s
    }

    private static func send(_ address: String, method: String, form: [String: String]? = nil,
                             token: String? = nil) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: address)!, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, answer)
    }

    private static func detail(_ answer: [String: Any], _ status: Int) -> String {
        answer["error_description"] as? String ?? answer["error"] as? String ?? "error \(status)"
    }
}
