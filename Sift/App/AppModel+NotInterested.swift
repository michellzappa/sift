import Foundation

/// Not interested, snooze and forget (owner, 2026-11-17: TikTok's "Not
/// interested", made visible): each choice changes one number you can see.
extension AppModel {
    enum LessOf: String, Sendable { case source, topic, story }

    /// Signal events without the ones of feeds you asked Sift to forget.
    func signalEvents() -> [SignalEvent] {
        let forgot = state.forgotSignals
        return FeedSignals.loadAll().filter { e in forgot[e.feedID].map { e.at > $0 } ?? true }
    }

    /// Not interested in a pick, with a reason. It also counts as seen.
    /// - source: a "less" signal on its feed (-1.5 to affinity, fades in a month)
    /// - topic: its theme costs 0.5 instead of lifting, for 30 days
    /// - story: items sharing 3+ words with it stay out for 7 days
    func notInterested(_ pick: TodayPick, _ reason: LessOf) {
        let now = Date()
        switch reason {
        case .source:
            signal(pick, "less")
            note("Less from \(pick.feedTitle)")
        case .topic:
            guard let theme = pick.why?.theme else { return notInterested(pick, .story) }
            state.muted.removeAll { $0.kind == "theme" && $0.value == theme }
            state.muted.append(Muted(kind: "theme", value: theme, until: now.addingTimeInterval(TodayBuilder.mutedThemeDays * 86_400)))
            note("Less about \(theme) for \(Int(TodayBuilder.mutedThemeDays)) days")
        case .story:
            state.muted.append(Muted(kind: "story", value: pick.title, words: Array(TodayBuilder.words(pick.title + " " + pick.summary)),
                                     url: pick.url, until: now.addingTimeInterval(TodayBuilder.mutedStoryDays * 86_400)))
            note("Enough of this story for a week")
        }
        state.muted.removeAll { $0.until < now }
        setSeen([pick.url], true)
        // Held-back items leave Today now, not at the next update.
        if var today = state.today {
            let muted = state.muted
            today.picks.removeAll { p in
                p.url == pick.url || (!isSeen(p.url) && TodayBuilder.isMutedStory(url: p.url, title: p.title, summary: p.summary, muted: muted, now: now))
            }
            state.today = today
        }
        refreshToday(force: reason == .topic)
        writeTodayForPhone()
    }

    var isDiscoverySnoozed: Bool { (state.discoverySnoozedUntil ?? .distantPast) > Date() }

    func snoozeDiscovery(_ on: Bool) {
        state.discoverySnoozedUntil = on ? Date().addingTimeInterval(7 * 86_400) : nil
        note(on ? "Discovery snoozed for a week: only your feeds' own picks" : "Discovery is back")
        refreshToday(force: true)
    }

    /// Forgets what Sift learned from a feed: its signals before now no
    /// longer count.
    func forgetSignals(_ feed: Feed) {
        state.forgotSignals[feed.id] = Date()
        note("Sift forgot what it learned from \(feed.title)")
        refreshToday(force: true)
    }
}
