import Foundation

/// Today, themes first (issue #41): the theme and network of each pick, and
/// the picks in theme sections (Engine/TodayThemes.swift).
extension AppModel {
    /// The theme each pick belongs to, by URL: the theme Today fitted it to
    /// (words or meaning, `PickWhy.theme`), else the top theme of the Your
    /// Graph creator its feed was followed from. Only current themes count.
    func todayThemes(_ picks: [TodayPick]) -> [String: String] {
        let names = Set(themes.map(\.name))
        let creatorTheme = Dictionary(creators.compactMap { c in c.themes.first.map { (c.id, $0.name) } },
                                      uniquingKeysWith: { a, _ in a })
        var feedTheme: [String: String] = [:]
        for feed in state.feeds {
            if let id = feed.creator, let t = creatorTheme[id] { feedTheme[feed.id] = t }
        }
        var out: [String: String] = [:]
        for pick in picks {
            if let t = pick.why?.theme, names.contains(t) {
                out[pick.url] = t
            } else if let t = feedTheme[pick.feedID], names.contains(t) {
                out[pick.url] = t
            }
        }
        return out
    }

    /// The picks in theme sections, best theme first, "Other" last.
    func todaySections(_ picks: [TodayPick]) -> [TodayThemes.Group<TodayPick>] {
        let theme = todayThemes(picks)
        return TodayThemes.group(picks, theme: { theme[$0.url] }, score: { $0.why?.score })
    }

    /// The network badge for a pick: the link's host, else its feed's provider.
    func network(of pick: TodayPick) -> Network {
        let feed = state.feeds.first { $0.id == pick.feedID }
        return Network.of(url: pick.url, provider: feed?.provider ?? feed.flatMap { AppModel.providerID(forFeed: $0.url) })
    }
}
