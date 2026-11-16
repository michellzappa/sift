import Foundation

extension AppModel {
    // MARK: My lists (owner, 2026-11-16)
    //
    // A feed of your own picks (a YouTube playlist you add to, any feed of
    // your saves) is Saved, not Offered: like Watch Later, it is what you
    // chose. A feed marked `mine` leaves Today and the Feeds sidebar and is
    // a Library source, "list:<feed id>", with the videos or links that are
    // in it now. One you take out of the list moves to Closed or Removed.

    nonisolated static let listPrefix = "list:"

    var myLists: [Feed] { state.feeds.filter { $0.mine == true } }

    /// Feeds that offer items: every followed feed except your lists.
    var offeredFeeds: [Feed] { state.feeds.filter { $0.mine != true } }

    var currentList: Feed? {
        guard let id = state.deviceID, id.hasPrefix(Self.listPrefix) else { return nil }
        return state.feeds.first { Self.listPrefix + $0.id == id }
    }

    /// The items in the list now, newest addition first.
    func listTabs(_ feed: Feed) -> [SafariTab] {
        let entries = FeedStore.entries(feed.id)
        let members = Set(FeedStore.members(feed.id) ?? entries.map(\.url))
        return entries.filter { members.contains($0.url) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .map { e in
                if previews[e.url] == nil {
                    previews[e.url] = Preview(title: e.title, text: e.summary, imageURL: e.image,
                                              site: URL(string: e.url)?.host() ?? "", fetched: .distantPast)
                }
                return SafariTab(url: e.url, title: e.title, lastViewed: e.date, source: Self.listPrefix + feed.id)
            }
    }

    /// Makes a feed one of your lists (Library) or an offered feed again (Today).
    func setMine(_ feed: Feed, _ mine: Bool) {
        guard let i = state.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        state.feeds[i].mine = mine ? true : nil
        if mine, FeedStore.members(feed.id) == nil {
            FeedStore.setMembers(FeedStore.entries(feed.id).map(\.url), for: feed.id)
        }
        refreshFeedCounts()
        refreshToday(force: true)
        reload()
        note(mine ? "\(feed.title) is now in your Library" : "\(feed.title) is now in Today")
    }
}
