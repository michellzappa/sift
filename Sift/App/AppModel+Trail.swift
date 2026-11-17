import Foundation

/// Trails (Engine/Trail.swift): "More Like This" from any saved link or
/// offered item.
extension AppModel {
    /// Saved links and recent feed items as trail nodes.
    func trailPool() -> [Trail.Node] {
        var out: [Trail.Node] = []
        for l in savedLinks() { out.append(trailNode(saved: l)) }
        let since = Date().addingTimeInterval(-Trail.offeredDays * 86_400)
        let creatorOf = creatorOfFeed
        for f in offeredFeeds where f.enabled {
            let c = creatorOf[f.id]
            for e in FeedStore.entries(f.id) where (e.date ?? .distantPast) >= since {
                let title = FeedParser.Text.title(e.title, body: e.summary)
                out.append(Trail.Node(url: e.url, title: title.isEmpty ? e.url : title, site: f.title, summary: e.summary,
                                      image: e.image, date: e.date, theme: nil, creator: c?.id ?? "feed:" + f.id,
                                      creatorName: c?.name ?? f.title, feedID: f.id, content: e.content,
                                      vector: embedSpace.unit[e.url]))
            }
        }
        return out
    }

    func trailNode(saved l: Creators.Link) -> Trail.Node {
        let p = previews[l.url]
        let key = Creators.key(l)
        let host = URL(string: l.url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        return Trail.Node(url: l.url, title: l.title.isEmpty ? l.url : l.title, site: p?.site ?? host, summary: p?.text ?? "",
                          image: p?.imageURL, date: l.date, theme: l.theme, creator: key?.id, creatorName: key?.name,
                          vector: embedSpace.unit[l.url])
    }

    /// The node for any address: a saved link, a feed item or a Today pick.
    func trailNode(url: String, pick: TodayPick? = nil) -> Trail.Node {
        if let l = savedLinks().first(where: { $0.url == url }) { return trailNode(saved: l) }
        let pick = pick ?? todayPicks.first { $0.url == url }
        let c = pick.flatMap { creatorOfFeed[$0.feedID] }
        let link = Creators.Link(url: url, title: pick?.title ?? url, date: pick?.date ?? Date(), theme: nil, author: nil)
        let key = Creators.key(link)
        let themeName = pick?.why?.theme
        return Trail.Node(url: url, title: pick?.title ?? url, site: pick?.feedTitle ?? "", summary: pick?.summary ?? "",
                          image: pick?.image, date: pick?.date, theme: themeName,
                          creator: c?.id ?? pick.map { "feed:" + $0.feedID } ?? key?.id,
                          creatorName: c?.name ?? pick?.feedTitle ?? key?.name, feedID: pick?.feedID,
                          vector: embedSpace.unit[url])
    }

    /// Opens the trail from one item and shows it.
    func openTrail(url: String, pick: TodayPick? = nil) {
        let seed = trailNode(url: url, pick: pick)
        let picks = Trail.build(seed: seed, pool: trailPool(), isSeen: { self.isSeen($0) })
        let followedIDs = Creators.followed(state.feeds)
        var creatorID = seed.creator
        if let id = creatorID, id.hasPrefix("feed:") { creatorID = creatorOfFeed[String(id.dropFirst(5))]?.id }
        let followed = seed.feedID != nil || (creatorID.map { followedIDs[$0] != nil } ?? false)
        trail = TrailState(seed: seed, picks: picks, creatorID: creatorID, followed: followed)
        navigationRequest = .trail
    }

    /// Follows the creator the trail started from.
    func followTrailCreator() {
        guard let t = trail else { return }
        if let id = t.creatorID, let c = creators.first(where: { $0.id == id }) {
            followCreator(c)
        } else if let input = AppModel.followInput(forLink: t.seed.url) {
            followQuick(input)
        }
        trail?.followed = true
    }
}
