import Foundation

/// Sift's Bluesky sign-in, for light actions only: like a post and save it
/// to the person's Bluesky bookmarks.
///
/// Why an app password and not OAuth: atproto OAuth requires PAR, DPoP and
/// a `client_id` that is an https address of a hosted client-metadata JSON
/// document. Sift has no server for that file (north star: no Sift
/// server). The spec's loopback exception (`client_id` http://localhost)
/// is optional for each authorization server and gives untrusted,
/// short-lived sessions. So Sift uses an app password that the person makes
/// at bsky.app (Settings > Privacy and security > App passwords) and can
/// revoke there. It is never the account password. The keychain keeps it
/// (service `app.sift.bluesky`) with the session tokens, so Sift can sign in
/// again when the refresh token expires.
enum BlueskyAccount {
    static let service = "app.sift.bluesky"
    /// Bookmarks and viewer state live on the Bluesky AppView; the PDS
    /// passes the call on when this header is set.
    private static let appView = "did:web:api.bsky.app#bsky_appview"
    private static let publicAPI = "https://public.api.bsky.app"

    struct Session: Codable, Sendable {
        var did: String
        var handle: String
        var pds: String
        var appPassword: String
        var access: String
        var refresh: String
    }

    /// One post as the signed-in person sees it.
    struct PostState: Sendable, Equatable {
        var uri: String
        var cid: String
        /// The person's like record, when they liked the post.
        var likeURI: String?
        var bookmarked: Bool
    }

    static func load() -> Session? {
        guard let s = Keychain.read(service: service) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: Data(s.utf8))
    }

    private static func store(_ session: Session?) {
        let text = session.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        Keychain.save(text, service: service)
    }

    // MARK: Sign-in

    /// "name", "@name.bsky.social", "name.com" or a DID.
    static func normalize(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("@") { t.removeFirst() }
        if !t.isEmpty, !t.hasPrefix("did:"), !t.contains(".") { t += ".bsky.social" }
        return t
    }

    static func signIn(identifier: String, appPassword: String) async throws -> Session {
        guard !Demo.isOn else { throw SendFailure(message: Demo.offMessage) }
        let id = normalize(identifier)
        let password = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !password.isEmpty else { throw SendFailure(message: "Type your handle and an app password.") }
        let did = try await resolveHandle(id)
        let pds = await pdsEndpoint(did) ?? "https://bsky.social"
        let session = try await createSession(pds: pds, identifier: did, password: password)
        store(session)
        return session
    }

    static func signOut() async {
        if let s = load(), !Demo.isOn {
            var request = URLRequest(url: URL(string: s.pds + "/xrpc/com.atproto.server.deleteSession")!, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("Bearer \(s.refresh)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        store(nil)
    }

    private static func createSession(pds: String, identifier: String, password: String) async throws -> Session {
        let (status, answer) = try await send(pds + "/xrpc/com.atproto.server.createSession", method: "POST",
                                              body: ["identifier": identifier, "password": password])
        guard status == 200, let access = answer["accessJwt"] as? String, let refresh = answer["refreshJwt"] as? String,
              let did = answer["did"] as? String
        else {
            if status == 401 { throw SendFailure(message: "Bluesky did not accept that handle and app password.") }
            throw SendFailure(message: "Bluesky sign-in failed: \(detail(answer, status))")
        }
        return Session(did: did, handle: answer["handle"] as? String ?? identifier, pds: pds,
                       appPassword: password, access: access, refresh: refresh)
    }

    /// New tokens from the refresh token, else a new session from the app
    /// password. Stored each time.
    private static func renew(_ s: Session) async throws -> Session {
        var request = URLRequest(url: URL(string: s.pds + "/xrpc/com.atproto.server.refreshSession")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(s.refresh)", forHTTPHeaderField: "Authorization")
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let access = answer["accessJwt"] as? String, let refresh = answer["refreshJwt"] as? String {
            var next = s
            next.access = access
            next.refresh = refresh
            store(next)
            return next
        }
        let next = try await createSession(pds: s.pds, identifier: s.did, password: s.appPassword)
        store(next)
        return next
    }

    /// The DID for a handle; a DID comes back as it is.
    private static func resolveHandle(_ handle: String) async throws -> String {
        if handle.hasPrefix("did:") { return handle }
        var c = URLComponents(string: publicAPI + "/xrpc/com.atproto.identity.resolveHandle")!
        c.queryItems = [.init(name: "handle", value: handle)]
        let (status, answer) = try await send(c.url!.absoluteString, method: "GET", body: nil)
        guard status == 200, let did = answer["did"] as? String else {
            throw SendFailure(message: "Bluesky does not know the handle \(handle).")
        }
        return did
    }

    /// The account's own server, from its DID document.
    private static func pdsEndpoint(_ did: String) async -> String? {
        let address: String
        if did.hasPrefix("did:plc:") { address = "https://plc.directory/\(did)" }
        else if did.hasPrefix("did:web:") { address = "https://\(did.dropFirst(8))/.well-known/did.json" }
        else { return nil }
        guard let reply = try? await send(address, method: "GET", body: nil), reply.0 == 200,
              let services = reply.1["service"] as? [[String: Any]] else { return nil }
        let pds = services.first { ($0["id"] as? String)?.hasSuffix("#atproto_pds") == true }
        return (pds?["serviceEndpoint"] as? String).map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
    }

    // MARK: Light actions

    /// The post behind a bsky.app link, with the person's like and bookmark.
    static func post(_ url: String) async throws -> PostState {
        guard let link = Networks.blueskyPost(url) else { throw SendFailure(message: "This is not a Bluesky post link.") }
        let did = try await resolveHandle(link.actor)
        let uri = "at://\(did)/app.bsky.feed.post/\(link.rkey)"
        let answer = try await xrpc("app.bsky.feed.getPosts", query: [.init(name: "uris", value: uri)], body: nil, proxy: true)
        guard let post = (answer["posts"] as? [[String: Any]])?.first, let cid = post["cid"] as? String else {
            throw SendFailure(message: "Bluesky did not find this post. It may be deleted.")
        }
        let viewer = post["viewer"] as? [String: Any] ?? [:]
        return PostState(uri: post["uri"] as? String ?? uri, cid: cid,
                         likeURI: viewer["like"] as? String, bookmarked: viewer["bookmarked"] as? Bool ?? false)
    }

    static func setLike(_ on: Bool, _ post: PostState) async throws -> PostState {
        guard let s = load() else { throw SendFailure(message: "Sign in to Bluesky in Settings > Inputs first.") }
        var next = post
        if on {
            let record: [String: Any] = [
                "$type": "app.bsky.feed.like",
                "subject": ["uri": post.uri, "cid": post.cid],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ]
            let answer = try await xrpc("com.atproto.repo.createRecord", query: nil,
                                        body: ["repo": s.did, "collection": "app.bsky.feed.like", "record": record], proxy: false)
            next.likeURI = answer["uri"] as? String
        } else if let like = post.likeURI, let rkey = like.split(separator: "/").last {
            _ = try await xrpc("com.atproto.repo.deleteRecord", query: nil,
                               body: ["repo": s.did, "collection": "app.bsky.feed.like", "rkey": String(rkey)], proxy: false)
            next.likeURI = nil
        }
        return next
    }

    /// Bluesky bookmarks are private: only the person sees them.
    static func setBookmark(_ on: Bool, _ post: PostState) async throws -> PostState {
        if on {
            _ = try await xrpc("app.bsky.bookmark.createBookmark", query: nil, body: ["uri": post.uri, "cid": post.cid], proxy: true)
        } else {
            _ = try await xrpc("app.bsky.bookmark.deleteBookmark", query: nil, body: ["uri": post.uri], proxy: true)
        }
        var next = post
        next.bookmarked = on
        return next
    }

    // MARK: Requests

    /// One call on the person's PDS (a GET with `query`, else a POST with
    /// `body`). An expired token is renewed once.
    private static func xrpc(_ method: String, query: [URLQueryItem]?, body: [String: Any]?, proxy: Bool) async throws -> [String: Any] {
        guard !Demo.isOn else { throw SendFailure(message: Demo.offMessage) }
        guard var s = load() else { throw SendFailure(message: "Sign in to Bluesky in Settings > Inputs first.") }
        var renewed = false
        while true {
            var c = URLComponents(string: s.pds + "/xrpc/" + method)!
            c.queryItems = query
            let (status, answer) = try await send(c.url!.absoluteString, method: body == nil ? "GET" : "POST", body: body,
                                                  token: s.access, proxy: proxy ? appView : nil)
            let expired = status == 401 || (status == 400 && (answer["error"] as? String) == "ExpiredToken")
            if expired, !renewed { s = try await renew(s); renewed = true; continue }
            guard (200..<300).contains(status) else { throw SendFailure(message: "Bluesky said: \(detail(answer, status))") }
            return answer
        }
    }

    private static func send(_ address: String, method: String, body: [String: Any]?,
                             token: String? = nil, proxy: String? = nil) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: address)!, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let proxy { request.setValue(proxy, forHTTPHeaderField: "atproto-proxy") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, answer)
    }

    private static func detail(_ answer: [String: Any], _ status: Int) -> String {
        answer["message"] as? String ?? answer["error"] as? String ?? "error \(status)"
    }
}
