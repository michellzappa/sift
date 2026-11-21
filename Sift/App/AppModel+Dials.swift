import Foundation

/// Theme dials (Engine/Dials.swift): the setting and the sources Sift tries.
extension AppModel {
    func dial(of theme: String) -> ThemeDial {
        ThemeDial(state.extraProjects.first { $0.name == theme }?.dial)
    }

    var themeDials: [String: ThemeDial] {
        var out: [String: ThemeDial] = [:]
        for t in themes { out[t.name] = ThemeDial(t.dial) }
        return out
    }

    func setDial(_ dial: ThemeDial, for theme: String) {
        guard let i = state.extraProjects.firstIndex(where: { $0.name == theme }) else { return }
        state.extraProjects[i].dial = dial == .stay ? nil : dial.rawValue
        refreshTrials()
        refreshToday(force: true)
        writeCreatorsForPhone()
    }

    var trialFeeds: [Feed] { state.feeds.filter { $0.trial != nil } }

    func trialFeeds(for theme: String) -> [Feed] { trialFeeds.filter { $0.trial == theme } }

    /// What Sift could try for one theme, best first, sources mixed.
    func trialCandidates(_ theme: String, _ dial: ThemeDial) -> [Trials.Candidate] {
        switch dial {
        case .stay:
            return []
        case .leanIn:
            let hidden = Set(state.hiddenCreators)
            return visibleCreators.filter { c in c.feedID == nil && !hidden.contains(c.id) && c.themes.contains { $0.name == theme } }
                // Central to what you follow first (graph rank), then saves in the theme.
                .sorted { a, b in
                    ((creatorRank[a.id] ?? 0), (a.themes.first { $0.name == theme }?.count ?? 0))
                        > ((creatorRank[b.id] ?? 0), (b.themes.first { $0.name == theme }?.count ?? 0))
                }
                .map { Trials.Candidate(id: $0.id, name: $0.name, input: $0.input, source: "you saved \($0.count) from them") }
        case .explore:
            let near = visibleNeighbors.filter { n in n.themes.contains { $0.name == theme } }
                .map { Trials.Candidate(id: $0.id, name: $0.name, input: $0.input, source: "Next Door") }
            let dir = directoryShown.filter { $0.theme == theme }
                .map { Trials.Candidate(id: "directory:" + $0.id, name: $0.name, input: $0.input, source: "Directory") }
            let far = (farther[theme]?.suggestions ?? []).filter { $0.hasFeed == true }
                .map { Trials.Candidate(id: "farther:" + $0.id, name: $0.name, input: $0.input, source: "Farther") }
            // One from each source in turn.
            var out: [Trials.Candidate] = []
            for i in 0..<max(near.count, dir.count, far.count) {
                for list in [near, dir, far] where i < list.count { out.append(list[i]) }
            }
            return out
        }
    }

    /// Ends tries that ran out or whose theme went back to Stay, then starts
    /// new ones up to each dial's count. At most `Trials.maxTotal` in all.
    func refreshTrials() {
        guard !Demo.isOn else { return }
        let dials = themeDials
        let now = Date()
        for f in trialFeeds {
            let theme = f.trial ?? ""
            if ThemeDial(dials[theme]?.rawValue) == .stay || (f.trialUntil ?? now) < now {
                state.triedSources.append(f.url)
                removeFeed(f)
            }
        }
        var plan: [(theme: String, candidate: Trials.Candidate)] = []
        var total = trialFeeds.count
        let tried = Set(state.triedSources)
        for (theme, dial) in dials.sorted(by: { $0.key < $1.key }) where dial != .stay {
            var need = dial.trials - trialFeeds(for: theme).count
            for c in trialCandidates(theme, dial) where need > 0 && total < Trials.maxTotal {
                guard !tried.contains(c.id), !tried.contains(c.input) else { continue }
                plan.append((theme, c))
                need -= 1
                total += 1
            }
        }
        guard !plan.isEmpty else { return }
        Task {
            for (theme, c) in plan {
                state.triedSources.append(c.id)
                guard let found = await FeedProviders.resolve(c.input).first,
                      !state.feeds.contains(where: { $0.url == found.url }) else { continue }
                addFeed(found)
                if let i = state.feeds.firstIndex(where: { $0.url == found.url }) {
                    state.feeds[i].trial = theme
                    state.feeds[i].trialSource = c.source
                    state.feeds[i].trialUntil = Date().addingTimeInterval(Trials.days * 86_400)
                }
            }
            await fetchFeeds(force: false)
            refreshToday()
            writeCreatorsForPhone()
        }
    }

    /// Makes a tried source a real follow.
    func followTrial(_ feed: Feed) {
        guard let i = state.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        state.feeds[i].trial = nil
        state.feeds[i].trialSource = nil
        state.feeds[i].trialUntil = nil
        noteFollowed(feed.title)
        refreshFeedCounts()
        writeFeedsForPhone()
        writeCreatorsForPhone()
    }

    /// Ends a try now; Sift does not try it again.
    func stopTrial(_ feed: Feed) {
        state.triedSources.append(feed.url)
        removeFeed(feed)
        refreshTrials()
        refreshToday(force: true)
        writeCreatorsForPhone()
    }

    /// Keeping an item from a tried source gives it two more weeks.
    func extendTrial(feedID: String) {
        guard let i = state.feeds.firstIndex(where: { $0.id == feedID }), state.feeds[i].trial != nil else { return }
        state.feeds[i].trialUntil = Date().addingTimeInterval(Trials.days * 86_400)
    }
}
