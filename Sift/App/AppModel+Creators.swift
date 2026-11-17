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

    /// Builds the graph from every saved link: the archive and the links of
    /// the current source. Errands, dropped and merged links do not count.
    func refreshCreators() {
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
        let kept = links.values.filter { l in
            state.mergedInto[l.url] == nil && !hiddenProjects.contains(state.assignments[l.url]?.project ?? "")
        }
        let followed = Creators.followed(state.feeds)
        creators = Creators.build(Array(kept), followed: followed)
        var byFeed: [String: Creator] = [:]
        for c in creators { if let f = c.feedID { byFeed[f] = c } }
        creatorOfFeed = byFeed
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
