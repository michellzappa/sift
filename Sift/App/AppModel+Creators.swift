import Foundation

/// Your Graph (Feeds/Creators.swift): building it, following, hiding.
extension AppModel {
    /// Creators not hidden, best score first.
    var visibleCreators: [Creator] {
        let hidden = Set(state.hiddenCreators)
        return creators.filter { !hidden.contains($0.id) }
    }

    var hiddenCreatorList: [Creator] {
        let hidden = Set(state.hiddenCreators)
        return creators.filter { hidden.contains($0.id) }
    }

    /// Builds the graph from every saved link (`savedLinks`).
    func refreshCreators() {
        let kept = savedLinks()
        // Sources a theme dial only tries are not follows.
        let followed = Creators.followed(state.feeds.filter { $0.trial == nil })
        creators = Creators.build(Array(kept), followed: followed)
        var byFeed: [String: Creator] = [:]
        for c in creators { if let f = c.feedID { byFeed[f] = c } }
        creatorOfFeed = byFeed
        writeCreatorsForPhone()
    }

    /// Follows a creator: the matching provider finds the feed, and the feed
    /// remembers the creator it came from.
    func followCreator(_ creator: Creator) {
        guard !Demo.isOn else { exportMessage = Demo.offMessage; return }
        Task {
            guard let found = await FeedProviders.resolve(creator.input).first else {
                note("No feed found for \(creator.name)")
                return
            }
            if let i = state.feeds.firstIndex(where: { $0.url == found.url }) {
                state.feeds[i].creator = creator.id
            } else {
                addFeed(found)
                if let i = state.feeds.firstIndex(where: { $0.url == found.url }) { state.feeds[i].creator = creator.id }
                noteFollowed(creator.name)
            }
            refreshCreators()
            refreshFeedCounts()
            refreshToday()
        }
    }

    func unfollowCreator(_ creator: Creator) {
        guard let id = creator.feedID, let feed = state.feeds.first(where: { $0.id == id }) else { return }
        removeFeed(feed)
        refreshCreators()
    }

    func setCreatorHidden(_ creator: Creator, _ hidden: Bool) {
        state.hiddenCreators.removeAll { $0 == creator.id }
        if hidden { state.hiddenCreators.append(creator.id) }
        writeCreatorsForPhone()
    }

    /// Fills `Library.Entry.author` from each file's front matter, once, for
    /// entries captured before the index kept it.
    func backfillAuthors() async {
        let key = "library.authorsV1"
        guard !Demo.isOn, !UserDefaults.standard.bool(forKey: key) else { return }
        let todo = library.filter { $0.value.author == nil && !$0.value.file.isEmpty }.map { ($0.key, $0.value.file) }
        let found: [String: String] = await Task.detached {
            var out: [String: String] = [:]
            for (url, file) in todo {
                guard let handle = try? FileHandle(forReadingFrom: Library.folder.appending(path: file)),
                      let data = try? handle.read(upToCount: 4096) else { continue }
                try? handle.close()
                let head = String(decoding: data, as: UTF8.self)
                guard let r = head.range(of: #"(?m)^author: (.*)$"#, options: .regularExpression) else { continue }
                var v = String(head[r].dropFirst("author: ".count)).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
                    v = String(v.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
                }
                // Captures before 1.7.2 kept YouTube's & as "u0026".
                v = v.replacingOccurrences(of: "u0026", with: "&").replacingOccurrences(of: "u0027", with: "'")
                if !v.isEmpty { out[url] = v }
            }
            return out
        }.value
        for (url, author) in found { library[url]?.author = author }
        Library.saveIndex(library)
        UserDefaults.standard.set(true, forKey: key)
        refreshCreators()
    }
}

/// Every saved link with its theme and author: the archive and the links of
/// the current source. Errands, dropped and merged links do not count. Your
/// Graph and trails read the same list.
extension AppModel {
    func savedLinks() -> [Creators.Link] {
        var links: [String: Creators.Link] = [:]
        let themeNames = Set(themes.map(\.name))
        func theme(_ url: String, fallback: String?) -> String? {
            if let p = state.assignments[url]?.project { return themeNames.contains(p) ? p : nil }
            return fallback.flatMap { themeNames.contains($0) ? $0 : nil }
        }
        func author(_ url: String) -> String? {
            if let a = library[url]?.author { return a }
            // Videos not captured yet: oEmbed's "By <channel>" preview.
            if let t = previews[url]?.text, t.hasPrefix("By ") { return String(t.dropFirst(3)) }
            return nil
        }
        for r in archive.values {
            links[r.url] = Creators.Link(url: r.url, title: r.title, date: r.firstSeen, theme: theme(r.url, fallback: r.theme), author: author(r.url))
        }
        for t in tabs where links[t.url] == nil {
            links[t.url] = Creators.Link(url: t.url, title: t.title, date: t.lastViewed ?? Date(), theme: theme(t.url, fallback: nil), author: author(t.url))
        }
        let hiddenProjects: Set<String> = [Project.errands, Project.drop]
        return links.values.filter { l in
            state.mergedInto[l.url] == nil && !hiddenProjects.contains(state.assignments[l.url]?.project ?? "")
        }
    }
}

/// Next door (Feeds/Creators.swift, `NextDoor`).
extension AppModel {
    var visibleNeighbors: [Neighbor] {
        let hidden = Set(state.hiddenCreators)
        let followed = Set(state.feeds.compactMap(\.creator))
        return neighbors.filter { !hidden.contains($0.id) && !followed.contains($0.id) }
    }

    /// Reads the saved text of every creator in Your Graph and the items of
    /// every followed feed, and counts who they link to. At most once an
    /// hour unless `force`.
    func refreshNeighbors(force: Bool = false) async {
        guard !Demo.isOn, !isFindingNeighbors else { return }
        if !force, let built = neighborsBuilt, Date().timeIntervalSince(built) < 3600 { return }
        isFindingNeighbors = true
        defer { isFindingNeighbors = false; neighborsBuilt = Date() }
        struct Plan: Sendable { var id, name: String; var score: Double; var themes: [String]; var urls: [(String, String)]; var feedID: String? }
        var plans: [Plan] = creators.prefix(300).map { c in
            Plan(id: c.id, name: c.name, score: c.score, themes: c.themes.prefix(3).map(\.name),
                 urls: c.saves.prefix(NextDoor.perCreator).map { ($0.title, $0.url) }, feedID: c.feedID)
        }
        let mapped = Set(creators.compactMap(\.feedID))
        for f in offeredFeeds where !mapped.contains(f.id) {
            plans.append(Plan(id: "feed:" + f.id, name: f.title, score: 1, themes: [], urls: [], feedID: f.id))
        }
        let known = Set(creators.map(\.id)).union(state.feeds.compactMap(\.creator))
        let result: [Neighbor] = await Task.detached(priority: .utility) {
            var sources: [NextDoor.Source] = []
            for p in plans {
                var texts: [(title: String, url: String, text: String)] = []
                for (title, url) in p.urls {
                    if let t = Library.text(for: url) { texts.append((title, url, t)) }
                }
                if let id = p.feedID {
                    for e in FeedStore.entries(id).prefix(NextDoor.perCreator) {
                        texts.append((e.title, e.url, e.content ?? e.summary))
                    }
                }
                if !texts.isEmpty { sources.append(NextDoor.Source(id: p.id, name: p.name, score: p.score, themes: p.themes, texts: texts)) }
            }
            return NextDoor.build(sources, known: known)
        }.value
        neighbors = result
        writeCreatorsForPhone()
    }

    func followNeighbor(_ n: Neighbor) {
        followCreator(Creator(id: n.id, kind: n.kind, name: n.name, input: n.input, saves: [], themes: n.themes,
                              score: n.score, recent: 0, feedID: nil))
    }

    func setNeighborHidden(_ n: Neighbor, _ hidden: Bool) {
        state.hiddenCreators.removeAll { $0 == n.id }
        if hidden { state.hiddenCreators.append(n.id) }
        writeCreatorsForPhone()
    }
}

/// Farther (Feeds/Farther.swift): Claude's suggestions per theme.
extension AppModel {
    /// The text Farther would send for a theme: the newest saved titles, the
    /// creators of the theme, and everything already followed.
    func fartherPrompt(_ theme: Project) -> String {
        let links = state.assignments.filter { $0.value.project == theme.name }.keys
        let titled: [(Date, String)] = links.compactMap { url in
            let r = archive[url]
            let title = [r?.title, previews[url]?.title].compactMap { $0 }.first { !$0.isEmpty && !$0.hasPrefix("http") }
            guard let title else { return nil }
            return (r?.firstSeen ?? .distantPast, String(title.prefix(140)))
        }
        let titles = titled.sorted { $0.0 > $1.0 }.map(\.1)
        let inTheme = creators.filter { c in c.themes.contains { $0.name == theme.name } }
            .sorted { ($0.themes.first { $0.name == theme.name }?.count ?? 0) > ($1.themes.first { $0.name == theme.name }?.count ?? 0) }
        let names = inTheme.prefix(12).map(\.name)
        let already = Array(Set(state.feeds.map(\.title) + inTheme.prefix(40).map(\.name))).sorted()
        return Farther.prompt(theme: theme, titles: titles, creators: names, already: already)
    }

    /// Asks the user's Claude for sources one step beyond the theme, then
    /// checks each for a feed. Replaces the theme's earlier answer.
    func askFarther(_ theme: Project) async {
        guard !Demo.isOn else { exportMessage = Demo.offMessage; return }
        guard !fartherAsking.contains(theme.name) else { return }
        fartherAsking.insert(theme.name)
        defer { fartherAsking.remove(theme.name); writeCreatorsForPhone() }
        do {
            var result = try await Farther.ask(backend: state.backend, prompt: fartherPrompt(theme), theme: theme.name)
            farther[theme.name] = result
            for i in result.suggestions.indices {
                result.suggestions[i] = await Farther.check(result.suggestions[i])
                farther[theme.name] = result
            }
            Farther.save(farther)
        } catch {
            if ClaudeCodeRunner.needsLogin(error.localizedDescription) { exportMessage = ClaudeCodeRunner.loginMessage }
            else { exportMessage = "Farther: \(error.localizedDescription)" }
        }
    }

    func followFarther(_ s: FartherSuggestion, theme: String) {
        guard !Demo.isOn else { exportMessage = Demo.offMessage; return }
        followQuick(s.input)
        dropFarther(s, theme: theme)
    }

    /// Takes a suggestion off the theme's list (followed or not wanted).
    func dropFarther(_ s: FartherSuggestion, theme: String) {
        farther[theme]?.suggestions.removeAll { $0.id == s.id }
        Farther.save(farther)
        writeCreatorsForPhone()
    }
}
