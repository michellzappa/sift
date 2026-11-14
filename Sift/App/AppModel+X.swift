import Foundation

extension AppModel {
    // MARK: X API (opt-in, the user's own X developer app)

    static let xBookmarksSourceID = "x-bookmarks"
    var isXBookmarks: Bool { state.deviceID == Self.xBookmarksSourceID }

    /// True when the user connected their own X app and signed in.
    var xConnected: Bool { !state.xClientID.isEmpty && state.xUserID != nil }

    func connectX() async {
        guard !Demo.isOn else { xError = Demo.offMessage; return }
        guard !state.xClientID.isEmpty else { xError = "Paste your X app's Client ID first."; return }
        xBusy = true
        defer { xBusy = false }
        do {
            _ = try await XAuth.signIn(clientID: state.xClientID)
            let me = try await XClient(clientID: state.xClientID).me()
            state.xUserID = me.id
            state.xUsername = me.username
            xError = nil
        } catch {
            xError = error.localizedDescription
        }
    }

    func disconnectX() {
        XAuth.store(nil)
        state.xUserID = nil
        state.xUsername = nil
        if isXBookmarks { state.deviceID = nil; reload() }
    }

    /// The cached post behind an X status URL, if any.
    func xPost(for url: String) -> XPost? { XClient.statusID(url).flatMap { xPosts[$0] } }

    /// Fetches posts that are missing or older than `XStore.maxAge`, in
    /// batches of 100, and turns them into previews. Posts the API no longer
    /// returns lose their content.
    func refreshXPosts(urls: [String], force: Bool = false) async {
        guard !Demo.isOn else { return }
        guard xConnected else { return }
        let ids = Array(Set(urls.compactMap(XClient.statusID))).filter { id in
            guard !force, let p = xPosts[id] else { return true }
            return Date().timeIntervalSince(p.fetched) > XStore.maxAge
        }
        guard !ids.isEmpty else { return }
        do {
            let result = try await XClient(clientID: state.xClientID).lookup(ids)
            for p in result.posts { xPosts[p.id] = p }
            for id in result.missing { xPosts[id] = .removedStub(id) }
            XStore.save(xPosts)
            for url in urls { if let p = xPost(for: url) { previews[url] = preview(from: p) } }
            PreviewFetcher.saveCache(previews)
        } catch {
            xError = error.localizedDescription
        }
    }

    private func preview(from p: XPost) -> Preview {
        if p.removed {
            return Preview(title: "", text: "", imageURL: nil, site: "x.com", fetched: p.fetched, failed: true)
        }
        let quoted = p.quotedID.flatMap { xPosts[$0] }
        let image = p.media.first.flatMap { $0.url ?? $0.preview } ?? quoted?.media.first.flatMap { $0.url ?? $0.preview }
        let text = XPostView.attributed(p).characters.map(String.init).joined()
        return Preview(title: p.author?.name ?? "X", text: text, imageURL: image, site: "x.com", fetched: p.fetched,
                       avatarURL: p.author?.avatar, links: p.links.filter { !$0.isMedia }.map(\.expanded))
    }

    /// Downloads the user's most recent bookmarks (X returns up to 800).
    func syncXBookmarks() async {
        guard !Demo.isOn else { return }
        guard xConnected, let userID = state.xUserID else { return }
        xBusy = true
        defer { xBusy = false }
        do {
            let result = try await XClient(clientID: state.xClientID).bookmarks(userID: userID)
            for p in result.posts { xPosts[p.id] = p }
            XStore.save(xPosts)
            xBookmarkIDs = result.order
            XStore.saveBookmarks(xBookmarkIDs)
            for id in result.order { if let p = xPosts[id] { previews[p.permalink] = preview(from: p) } }
            PreviewFetcher.saveCache(previews)
            xError = nil
            if isXBookmarks { reload() }
        } catch {
            xError = error.localizedDescription
        }
    }

    func xBookmarkTabs() -> [SafariTab] {
        xBookmarkIDs.compactMap { id in
            guard let p = xPosts[id], !p.removed else { return nil }
            let title = "\(p.author?.name ?? "X") on X: \(p.text.prefix(120))"
            return SafariTab(url: p.permalink, title: title, lastViewed: p.created)
        }
    }
}
