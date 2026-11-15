import AppKit
import Foundation
import UniformTypeIdentifiers

/// Feeds as a source: OPML import (all or a subset), add by URL, fetching
/// with the library jobs, export back to OPML. See Engine/Feeds.swift.
extension AppModel {
    var isFeeds: Bool { state.deviceID == FeedStore.sourceID }
    var feedCount: Int { state.feeds.filter(\.enabled).reduce(0) { $0 + FeedStore.entries($1.id).count } }

    /// Every enabled feed's items as links, newest first. Feed text and
    /// images fill the preview, so Sift need not fetch the page for a card.
    func feedTabs() -> [SafariTab] {
        var out: [SafariTab] = []
        for feed in state.feeds where feed.enabled {
            for e in FeedStore.entries(feed.id) {
                out.append(SafariTab(url: e.url, title: e.title.isEmpty ? e.url : e.title, lastViewed: e.date, source: FeedStore.sourceID))
                if previews[e.url] == nil, !e.summary.isEmpty || e.image != nil {
                    previews[e.url] = Preview(title: e.title, text: e.summary, imageURL: e.image,
                                              site: feed.title, fetched: Date())
                }
            }
        }
        return out.sorted { ($0.lastViewed ?? .distantPast) > ($1.lastViewed ?? .distantPast) }
    }

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
        if added > 0 { reload() }
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
                 category: $0.category, added: Date())
        }
        guard !new.isEmpty else { return }
        state.feeds += new
        Task { await fetchFeeds() }
    }

    /// Adds one feed found from a site or feed address.
    func addFeed(url: String, parsed: FeedParser.Parsed) {
        guard !state.feeds.contains(where: { $0.url == url }) else { return }
        let feed = Feed(id: UUID().uuidString.prefix(8).lowercased(), url: url,
                        title: parsed.title.isEmpty ? (URL(string: url)?.host() ?? url) : parsed.title,
                        site: parsed.site, added: Date(), lastFetched: Date())
        state.feeds.append(feed)
        _ = FeedStore.merge(parsed.entries, into: feed.id)
        reload()
    }

    func removeFeed(_ feed: Feed) {
        state.feeds.removeAll { $0.id == feed.id }
        FeedStore.remove(feed.id)
        reload()
    }

    func setFeed(_ feed: Feed, enabled: Bool) {
        guard let i = state.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        state.feeds[i].enabled = enabled
        reload()
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
