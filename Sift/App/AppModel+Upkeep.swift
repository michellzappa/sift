import Foundation

extension AppModel {
    // MARK: Duplicates, broken links, notes, saved searches

    static func duplicates(in tabs: [SafariTab]) -> [[SafariTab]] {
        Dictionary(grouping: tabs, by: { URLKey.normalize($0.url) }).values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.title ?? "") < ($1.first?.title ?? "") }
    }

    var duplicateTabs: [SafariTab] { duplicateGroups.flatMap { $0 } }

    /// Keeps one link per page: the one sorted by hand, else a sorted one,
    /// else the newest. The others hide; their theme, action and note move
    /// to the kept link when it has none.
    func mergeDuplicates() {
        for group in duplicateGroups {
            let keep = group.first { state.assignments[$0.url]?.manual == true }
                ?? group.first { state.assignments[$0.url] != nil }
                ?? group.max { ($0.lastViewed ?? .distantPast) < ($1.lastViewed ?? .distantPast) }!
            for tab in group where tab.url != keep.url {
                state.mergedInto[tab.url] = keep.url
                if state.assignments[keep.url] == nil, let a = state.assignments[tab.url] { state.assignments[keep.url] = a }
                if note(for: keep.url) == nil, let n = note(for: tab.url) { setNote(n, for: keep.url) }
            }
        }
        let gone = Set(state.mergedInto.keys)
        tabs.removeAll { gone.contains($0.url) }
    }

    /// Links whose page is gone (404, 410 or no such site).
    var brokenTabs: [SafariTab] {
        let urls = Set(library.filter { $0.value.status == "gone" }.map(\.key))
        return tabs.filter { urls.contains($0.url) } + archivedTabs.filter { urls.contains($0.url) }
    }

    /// The user's own note on a link. Kept in the archive, so it outlives the tab.
    func note(for url: String) -> String? {
        guard let n = archive[url]?.takeaway, !n.isEmpty else { return nil }
        return n
    }

    func setNote(_ note: String, for url: String) {
        guard archive[url] != nil else { return }
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        archive[url]?.takeaway = clean.isEmpty ? nil : clean
        ArchiveStore.save(archive)
        scheduleSearchIndex()
    }

    func saveSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !state.savedSearches.contains(q) else { return }
        state.savedSearches.append(q)
    }

    func removeSavedSearch(_ query: String) { state.savedSearches.removeAll { $0 == query } }

    /// A saved search's links, best match first, from every source and the archive.
    func links(matching query: String) async -> [SafariTab] {
        let hits = await searchLibrary(query)
        return hits.compactMap { h in tabs.first { $0.url == h.url } ?? archive[h.url]?.asTab }
    }

    // MARK: Search

    /// Rebuilds the search index a few seconds after the last change.
    func scheduleSearchIndex() {
        indexTask?.cancel()
        indexTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            let docs = archive.values.map { r in
                let a = state.assignments[r.url]
                let e = library[r.url]
                return SearchIndex.Doc(url: r.url, title: r.title, theme: a?.project ?? "", source: r.source,
                                       kind: e?.kind ?? "", saved: r.firstSeen, file: e?.file ?? "",
                                       also: a?.also ?? [], fallback: r.previewText, note: r.takeaway ?? "",
                                       summary: e?.summary ?? "")
            }
            let counts = Dictionary(grouping: state.assignments.values, by: \.project).mapValues(\.count)
            let themes = themes.map { SearchIndex.Theme(name: $0.name, summary: $0.summary, notes: $0.notes, memory: $0.memory, links: counts[$0.name] ?? 0) }
            await Task.detached(priority: .utility) { SearchIndex.rebuild(docs: docs, themes: themes) }.value
        }
    }

    /// Full-text matches, best first: url and a snippet of the matching text.
    func searchLibrary(_ query: String) async -> [SearchIndex.Hit] {
        await Task.detached { SearchIndex.search(query) }.value
    }

    func sortItem(_ tab: SafariTab) -> Sorter.Item {
        let p = previews[tab.url]
        let title = tab.hasUsefulTitle ? tab.title : (p?.title ?? "")
        var preview = p?.failed == false ? p?.text ?? "" : ""
        if let out = p?.outboundURL { preview += " (links to \(out))" }
        return Sorter.Item(url: tab.url, title: title, preview: preview)
    }

    /// Fetches previews for the tabs that have none yet, six at a time.
    func fetchPreviews(for list: [SafariTab], force: Bool = false) async {
        guard !Demo.isOn else { return }
        var todo = list.map(\.url).filter { force || previews[$0] == nil || needsLinks($0) }
        // With the X API connected, X posts come from the API in batches.
        if xConnected {
            let xURLs = todo.filter { XClient.statusID($0) != nil }
            if !xURLs.isEmpty {
                await refreshXPosts(urls: xURLs, force: force)
                todo.removeAll { XClient.statusID($0) != nil }
            }
        }
        guard !todo.isEmpty else { return }
        fetchingPreviews += todo.count
        let xSyndication = state.xSyndication
        await withTaskGroup(of: (String, Preview).self) { group in
            var iterator = todo.makeIterator()
            for _ in 0..<6 {
                guard let url = iterator.next() else { break }
                group.addTask { (url, await PreviewFetcher.fetch(url, xSyndication: xSyndication)) }
            }
            for await (url, preview) in group {
                previews[url] = preview
                fetchingPreviews -= 1
                if let next = iterator.next() { group.addTask { (next, await PreviewFetcher.fetch(next, xSyndication: xSyndication)) } }
            }
        }
        PreviewFetcher.saveCache(previews)
    }

    /// Turns the X syndication previews on or off. Turning them on drops the
    /// cached X previews that have no image (oEmbed never returns one) and
    /// fetches them again for the loaded tabs.
    func setXSyndication(_ on: Bool) {
        state.xSyndication = on
        guard on else { return }
        let stale = Set(previews.filter { $0.value.site == "x.com" && $0.value.imageURL == nil }.keys)
        guard !stale.isEmpty else { return }
        for url in stale { previews[url] = nil }
        PreviewFetcher.saveCache(previews)
        let refetch = tabs.filter { stale.contains($0.url) }
        Task { await fetchPreviews(for: refetch) }
    }

    func preview(for tab: SafariTab) async {
        if previews[tab.url] == nil || needsLinks(tab.url) { await fetchPreviews(for: [tab]) }
    }

    /// X previews cached before link extraction existed get one refetch.
    private func needsLinks(_ url: String) -> Bool {
        guard state.xSyndication, let p = previews[url] else { return false }
        return p.site == "x.com" && !p.failed && p.links == nil
    }

    /// Fetches previews for the "unknown" tabs, then sorts them again with the
    /// preview text. Tabs that stay unknown are probably deleted posts.
    func resortUnknown() async {
        guard !Demo.isOn else { return }
        let unknown = tabs(in: Project.unknown)
        guard !unknown.isEmpty, !isSorting else { return }
        await fetchPreviews(for: unknown)
        for tab in unknown { state.assignments[tab.url] = nil }
        await sortUnsorted()
    }
}
