import AppKit
import Foundation
import UniformTypeIdentifiers

/// Feeds: OPML import (all or a subset), add by URL, fetching with the
/// library jobs, export back to OPML. Feed items are offered, not saved:
/// they appear only in Today (AppModel+Today.swift). See Engine/Feeds.swift.
extension AppModel {
    /// Items held for all enabled feeds (Settings shows it).
    var feedCount: Int { state.feeds.filter(\.enabled).reduce(0) { $0 + FeedStore.entries($1.id).count } }

    // MARK: Fetching

    /// Fetches feeds not fetched in the last hour, one site at a time.
    /// Runs with the library jobs (reload and every 15 minutes).
    func fetchFeeds(force: Bool = false) async {
        guard !Demo.isOn, !isFetchingFeeds else { return }
        let due = state.feeds.filter { $0.enabled && (force || ($0.lastFetched ?? .distantPast) < Date().addingTimeInterval(-3600)) }
        guard !due.isEmpty else { return }
        isFetchingFeeds = true
        feedProgress = (0, due.count)
        defer { isFetchingFeeds = false }
        var added = 0
        for feed in due {
            let result = await FeedFetcher.fetch(feed)
            guard let i = state.feeds.firstIndex(where: { $0.id == feed.id }) else { continue }
            state.feeds[i].lastFetched = Date()
            switch result {
            case .items(let parsed, let etag, let modified):
                added += FeedStore.merge(parsed.entries, into: feed.id)
                state.feeds[i].etag = etag
                state.feeds[i].lastModified = modified
                state.feeds[i].lastError = nil
                if state.feeds[i].site == nil { state.feeds[i].site = parsed.site }
            case .unchanged:
                state.feeds[i].lastError = nil
            case .failed(let why):
                state.feeds[i].lastError = why
            }
            feedProgress.done += 1
        }
        // New items can only reach Today; they never enter sources or themes.
        // A forced check rebuilds Today so picks carry the newest text.
        if added > 0 || force { refreshToday(force: force) }
    }

    // MARK: Adding and removing

    /// Reads an OPML file and returns its feeds for the import sheet.
    func readOPML() -> [OPMLCandidate]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml, .xml, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an OPML file exported from your feed reader."
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return nil }
        let followed = Set(state.feeds.map(\.url))
        return FeedParser.opml(data).map {
            OPMLCandidate(url: $0.url, title: $0.title.isEmpty ? (URL(string: $0.url)?.host() ?? $0.url) : $0.title,
                          site: $0.site, category: $0.category, alreadyFollowed: followed.contains($0.url))
        }
    }

    /// Follows the chosen feeds and fetches them.
    func follow(_ candidates: [OPMLCandidate]) {
        let followed = Set(state.feeds.map(\.url))
        let new = candidates.filter { !followed.contains($0.url) }.map {
            Feed(id: UUID().uuidString.prefix(8).lowercased(), url: $0.url, title: $0.title, site: $0.site,
                 category: $0.category, provider: Self.providerID(forFeed: $0.url), added: Date())
        }
        guard !new.isEmpty else { return }
        state.feeds += new
        Task { await fetchFeeds() }
    }

    /// Follows a feed from a link: feed://host/path, feed:https://…,
    /// feeds://…, or sift://subscribe?url=<anything the Add sheet takes:
    /// r/swift, @name.bsky.social, a site>. The matching provider finds the
    /// feed; Sift says what it did.
    func subscribe(from link: URL) {
        guard !Demo.isOn else { exportMessage = Demo.offMessage; return }
        var target = link.absoluteString
        switch link.scheme?.lowercased() {
        case "sift":
            guard link.host() == "subscribe",
                  let u = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value
            else { return }
            target = u
        case "feed", "feeds":
            let rest = target.drop(while: { $0 != ":" }).dropFirst()
            target = rest.hasPrefix("//") ? "https:" + rest : String(rest)
        default:
            return
        }
        Task {
            guard let found = await FeedProviders.resolve(target).first else {
                note("No feed found at \(target)")
                return
            }
            if state.feeds.contains(where: { $0.url == found.url }) {
                note("Already following \(found.parsed.title)")
                return
            }
            addFeed(found)
            noteFollowed(found.parsed.title)
        }
    }

    /// Adds one feed a provider found (FeedProviders.resolve).
    func addFeed(_ found: FeedProviders.Found, category: String? = nil) {
        addFeed(url: found.url, parsed: found.parsed, provider: found.provider, title: found.label, category: category)
    }

    /// Adds one feed found from a site or feed address.
    func addFeed(url: String, parsed: FeedParser.Parsed, provider: String? = nil, title: String? = nil, category: String? = nil) {
        guard !state.feeds.contains(where: { $0.url == url }) else { return }
        let name = !parsed.title.isEmpty ? parsed.title : (title ?? URL(string: url)?.host() ?? url)
        let feed = Feed(id: UUID().uuidString.prefix(8).lowercased(), url: url, title: name,
                        site: parsed.site, category: category, provider: provider, added: Date(), lastFetched: Date())
        state.feeds.append(feed)
        _ = FeedStore.merge(parsed.entries, into: feed.id)
        refreshToday(force: true)
    }

    // MARK: Following from anywhere

    /// A short notice that fades, never a modal alert: following is quick
    /// and often comes in runs (suggestions, dropped links, feed:// links).
    func note(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
            self?.recentFollows = []
        }
    }

    /// "Following Simon Willison", then "Following Simon Willison and 2 more".
    func noteFollowed(_ title: String) {
        recentFollows.append(title)
        let first = recentFollows[0]
        note(recentFollows.count == 1 ? "Following \(first)" : "Following \(first) and \(recentFollows.count - 1) more")
    }

    /// What "Follow Site" follows for a link: r/name for Reddit, owner/repo
    /// for GitHub, the page itself for YouTube (the provider reads the
    /// channel), Bluesky and Mastodon profiles, else the site's host.
    static func followInput(forLink link: String) -> String? {
        guard let u = URL(string: link), let h = u.host()?.lowercased() else { return nil }
        let host = h.replacingOccurrences(of: #"^(www\.|m\.|old\.)"#, with: "", options: .regularExpression)
        let parts = u.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("reddit.com"), parts.count >= 2, parts[0] == "r" { return "r/\(parts[1])" }
        if host == "github.com", parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
        if host.hasSuffix("youtube.com") || host == "youtu.be" || host == "bsky.app" || host.hasSuffix("medium.com") { return link }
        if parts.first?.hasPrefix("@") == true { return "https://\(host)/\(parts[0])" }
        return host
    }

    /// A short name for the Follow Site menu item.
    static func followLabel(forLink link: String) -> String? {
        guard let input = followInput(forLink: link) else { return nil }
        if input.hasPrefix("http"), let u = URL(string: input) {
            let host = u.host()?.replacingOccurrences(of: "www.", with: "") ?? input
            return host.hasSuffix("youtube.com") || host == "youtu.be" ? "This YouTube Channel" : host
        }
        return input
    }

    /// Follows without the sheet: the first feed the matching provider
    /// finds. Says what happened in the message alert.
    func followQuick(_ input: String) {
        guard !Demo.isOn else { exportMessage = Demo.offMessage; return }
        Task {
            guard let found = await FeedProviders.resolve(input).first else {
                note("No feed found for \(input)")
                return
            }
            if state.feeds.contains(where: { $0.url == found.url }) {
                note("Already following \(found.parsed.title)")
                return
            }
            addFeed(found)
            noteFollowed(found.label ?? found.parsed.title)
        }
    }

    /// Sites, subreddits and repositories you save from often, not followed.
    var feedSuggestions: [FeedSuggestion] {
        var hosts = Set<String>()
        var inputs = Set<String>()
        for f in state.feeds {
            for raw in [f.url, f.site].compactMap({ $0 }) {
                if let h = URL(string: raw)?.host()?.lowercased() { hosts.insert(h.replacingOccurrences(of: "www.", with: "")) }
                if let i = Self.followInput(forLink: raw) { inputs.insert(i.lowercased()) }
            }
        }
        let urls = Array(archive.keys) + tabs.map(\.url)
        return FeedSuggestions.make(urls: Array(Set(urls)), followedHosts: hosts, followedInputs: inputs)
    }

    /// A provider for a feed address from OPML, by its host, for the icon.
    static func providerID(forFeed url: String) -> String? {
        guard let host = URL(string: url)?.host()?.lowercased() else { return nil }
        let rules: [(String, String)] = [("reddit.com", "reddit"), ("youtube.com", "youtube"), ("substack.com", "substack"),
                                         ("bsky.app", "bluesky"), ("medium.com", "medium"), ("tumblr.com", "tumblr"),
                                         ("github.com", "github"), ("arxiv.org", "arxiv"), ("hnrss.org", "hackernews"),
                                         ("ycombinator.com", "hackernews"), ("news.google.com", "news")]
        return rules.first { host.hasSuffix($0.0) }?.1
    }

    /// The feeds in a folder ("" = no folder), by title.
    func feeds(inFolder folder: String) -> [Feed] {
        state.feeds.filter { ($0.category ?? "") == folder }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var feedFolders: [String] { Array(Set(state.feeds.compactMap(\.category))).sorted() }

    /// Recent items of some feeds as Today-style picks (no reason line),
    /// newest first, for the sidebar's feed and folder lists.
    func items(of feeds: [Feed], limit: Int = 300) -> [TodayPick] {
        var out: [TodayPick] = []
        for f in feeds {
            for e in FeedStore.entries(f.id) {
                out.append(TodayPick(url: e.url, title: e.title.isEmpty ? e.url : e.title, date: e.date, feedID: f.id,
                                     feedTitle: f.title, summary: e.summary, image: e.image, reason: "", content: e.content))
            }
        }
        return Array(out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(limit))
    }

    func removeFeed(_ feed: Feed) {
        state.feeds.removeAll { $0.id == feed.id }
        FeedStore.remove(feed.id)
        refreshToday(force: true)
    }

    func setFeed(_ feed: Feed, enabled: Bool) {
        guard let i = state.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        state.feeds[i].enabled = enabled
        refreshToday(force: true)
    }

    /// Writes the followed feeds as OPML, so they can move to any reader.
    func exportOPML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sift feeds.opml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FeedParser.opml(state.feeds).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// A feed from an OPML file, before the user picks it.
struct OPMLCandidate: Identifiable, Hashable, Sendable {
    var id: String { url }
    var url: String
    var title: String
    var site: String?
    var category: String?
    var alreadyFollowed: Bool
}
