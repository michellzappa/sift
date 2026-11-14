import Foundation
import SwiftUI

extension AppModel {
    // MARK: Projects

    /// The themes Sift sorts into, in name order. Themes come from the
    /// user's own links; there is no fixed list.
    var projects: [Project] { themes.sorted { $0.name < $1.name } }

    var themes: [Project] { state.extraProjects.filter(\.isTheme) }

    /// Places links can end up, added by hand. Used only as hints when
    /// Claude suggests a home for a theme.
    var handPlaces: [Project] { state.extraProjects.filter { !$0.isTheme } }

    // MARK: Themes

    /// Reads every link Sift can see (the phone's tabs, the Reading List and Instagram Saved),
    /// fills in titles for bare links, and asks Claude for themes. The result
    /// waits in `themeProposal` until the user accepts it.
    func discoverThemes() async {
        guard !Demo.isOn else { sortError = Demo.offMessage; return }
        guard !isDiscovering, !isSorting else { return }
        isDiscovering = true
        sortError = nil
        defer { isDiscovering = false }

        var corpus: [SafariTab] = []
        var seen = Set<String>()
        func add(_ list: [SafariTab]) { for t in list where seen.insert(t.url).inserted { corpus.append(t) } }
        if let phone = devices.first, let phoneTabs = try? CloudTabsReader.tabs(deviceID: phone.id) { add(phoneTabs) }
        for profile in chromeProfiles { add(profile.tabs) }
        if let reading = try? ReadingListReader.items() {
            for item in reading where previews[item.tab.url] == nil { if let p = item.preview { previews[item.tab.url] = p } }
            add(reading.map(\.tab))
        }
        let instagram = instagramItems()
        for item in instagram where previews[item.tab.url] == nil { if let p = item.preview { previews[item.tab.url] = p } }
        add(instagram.map(\.tab))
        add(xBookmarkTabs())
        for source in state.importedSources {
            let items = importedItems(source)
            for item in items where previews[item.tab.url] == nil { if let p = item.preview { previews[item.tab.url] = p } }
            add(items.map(\.tab))
        }
        add(tabs)

        // Transactional tabs are not curiosity: they skip Claude entirely.
        corpus.removeAll { Errands.isErrand($0.url) }

        // Bare links (mostly X posts) say nothing without their text.
        await fetchPreviews(for: corpus.filter { !$0.hasUsefulTitle })

        do {
            let result = try await Sorter(backend: state.backend)
                .discoverThemes(corpus.map(sortItem), destinations: handPlaces + state.destinations.map { Project(name: $0.name, summary: $0.detail, isTheme: false) }, keep: themes)
            proposalURLs = corpus.map(\.url)
            themeProposal = result.sorted { $0.itemIDs.count > $1.itemIDs.count }
        } catch {
            sortError = error.localizedDescription
        }
    }

    /// Makes the accepted themes Sift's categories. Links in a "personal" or
    /// "noise" theme go to the personal and drop buckets. Links in a theme the
    /// user left out become unsorted. Uses and next actions stay.
    func applyThemes(_ accepted: [Sorter.ThemeProposal]) {
        var s = state
        let before = Dictionary(s.extraProjects.filter(\.isTheme).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let counts = Dictionary(grouping: s.assignments.values, by: \.project).mapValues(\.count)
        s.extraProjects.removeAll(where: \.isTheme)
        let acceptedIDs = Set(accepted.flatMap(\.itemIDs))
        // Links the user placed by hand stay where they are, as long as that
        // theme or bucket still exists after this run.
        let keptNames = Set(accepted.filter { !["noise", "personal", "errand"].contains($0.kind) }.map(\.name)).union(Project.buckets)
        func isKeptHandMove(_ url: String) -> Bool {
            guard let a = s.assignments[url], a.manual else { return false }
            return keptNames.contains(a.project)
        }
        for proposal in themeProposal ?? [] {
            let isAccepted = accepted.contains { $0.itemIDs == proposal.itemIDs }
            if !isAccepted {
                for id in proposal.itemIDs where proposalURLs.indices.contains(id) && !acceptedIDs.contains(id) {
                    if isKeptHandMove(proposalURLs[id]) { continue }
                    s.assignments[proposalURLs[id]] = nil
                }
            }
        }
        for theme in accepted {
            let bucket: String? = switch theme.kind {
            case "noise": Project.drop
            case "personal": Project.personal
            case "errand": Project.errands
            default: nil
            }
            let name = bucket ?? theme.name
            if bucket == nil {
                var p = Project(name: theme.name, summary: theme.description, destination: theme.destination)
                // Theme memory: notes and history follow the theme, also when
                // Claude renamed, merged or split it.
                let day = Date.now.formatted(.iso8601.year().month().day())
                let earlier = before[theme.name] ?? theme.continues.flatMap { before[$0] }
                if let earlier {
                    p.notes = earlier.notes
                    p.history = earlier.history
                    if earlier.name != theme.name { p.history.append("\(day): continues \(earlier.name)") }
                    p.history.append("\(day): rediscovered, \(theme.itemIDs.count) links (was \(counts[earlier.name] ?? 0))")
                } else {
                    p.history.append("\(day): found, \(theme.itemIDs.count) links")
                }
                s.extraProjects.append(p)
            }
            for id in theme.itemIDs where proposalURLs.indices.contains(id) {
                let url = proposalURLs[id]
                if isKeptHandMove(url) { continue }
                var a = s.assignments[url] ?? Assignment(project: name, use: "", manual: false, action: nil)
                a.project = name
                a.manual = false
                a.sortedBy = "claude"
                if bucket != nil { a.use = "" }
                s.assignments[url] = a
            }
        }
        // Themes changed: connections between them are found again.
        for url in s.assignments.keys { s.assignments[url]?.also = nil }
        state = s
        themeProposal = nil
        Task { await findConnections() }
    }

    /// The user's own notes on a theme.
    func setNotes(_ notes: String, for theme: String) {
        guard let i = state.extraProjects.firstIndex(where: { $0.name == theme }) else { return }
        state.extraProjects[i].notes = notes
    }

    /// Deletes one theme. Its links become unsorted.
    func removeTheme(_ name: String) {
        var s = state
        s.extraProjects.removeAll { $0.isTheme && $0.name == name }
        for (url, a) in s.assignments where a.project == name { s.assignments[url] = nil }
        state = s
    }

    func assignment(for tab: SafariTab) -> Assignment? { state.assignments[tab.url] }

    func tabs(in project: String?) -> [SafariTab] {
        guard let project else { return tabs.filter { state.assignments[$0.url] == nil } }
        return tabs.filter { state.assignments[$0.url]?.project == project }
    }

    var unsortedCount: Int { tabs.filter { state.assignments[$0.url] == nil }.count }

    func count(_ project: String) -> Int { tabs.filter { state.assignments[$0.url]?.project == project }.count }

    /// Projects that hold at least one tab, biggest first.
    var activeProjects: [(project: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tab in tabs { if let p = state.assignments[tab.url]?.project { counts[p, default: 0] += 1 } }
        return counts.filter { !Project.buckets.contains($0.key) }
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    func move(_ tab: SafariTab, to project: String) {
        let old = state.assignments[tab.url]
        let use = Project.buckets.contains(project) ? "" : (old?.use ?? "")
        let action = old?.action
        state.assignments[tab.url] = Assignment(project: project, use: use, manual: true, action: action, sortedBy: old?.sortedBy)
    }

    func setUse(_ use: String, for tab: SafariTab) {
        guard var a = state.assignments[tab.url] else { return }
        a.use = use
        a.manual = true
        state.assignments[tab.url] = a
    }

    /// Adds a theme by hand.
    func addTheme(name: String, summary: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !Project.buckets.contains(clean.lowercased()),
              !state.extraProjects.contains(where: { $0.name.lowercased() == clean.lowercased() }) else { return }
        var p = Project(name: clean, summary: summary)
        p.history = ["\(Date.now.formatted(.iso8601.year().month().day())): added by hand"]
        state.extraProjects.append(p)
    }

    func renameTheme(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != old, !state.extraProjects.contains(where: { $0.name == clean }) else { return }
        var s = state
        if let i = s.extraProjects.firstIndex(where: { $0.isTheme && $0.name == old }) {
            s.extraProjects[i].name = clean
            s.extraProjects[i].history.append("\(Date.now.formatted(.iso8601.year().month().day())): renamed from \(old)")
        }
        for (url, a) in s.assignments {
            if a.project == old { s.assignments[url]?.project = clean }
            if let also = a.also, also.contains(old) { s.assignments[url]?.also = also.map { $0 == old ? clean : $0 } }
        }
        state = s
    }

    // MARK: Sorting

    /// Sorts every tab that has no assignment yet. Hand-sorted tabs stay as they are.
    func sortUnsorted() async {
        guard !Demo.isOn else { sortError = Demo.offMessage; return }
        guard !isSorting else { return }
        let all = tabs.filter { state.assignments[$0.url] == nil }
        guard !all.isEmpty else { return }

        isSorting = true
        sortError = nil
        defer { isSorting = false }
        // Apple's on-device model first; Claude gets what it is unsure about.
        let handled = await sortOnDevice(all.map(sortItem))
        let todo = all.filter { !handled.contains($0.url) && state.assignments[$0.url] == nil }
        guard !todo.isEmpty else { Task { await findConnections() }; return }
        sortProgress = (0, todo.count)

        let sorter = Sorter(backend: state.backend)
        let projects = self.projects
        for start in stride(from: 0, to: todo.count, by: Sorter.batchSize) {
            let batch = Array(todo[start..<min(start + Sorter.batchSize, todo.count)])
            do {
                let result = try await sorter.sort(batch.map(sortItem), projects: projects)
                for (url, a) in result where state.assignments[url]?.manual != true {
                    state.assignments[url] = a
                }
                sortProgress.done = min(start + batch.count, todo.count)
            } catch {
                sortError = error.localizedDescription
                return
            }
        }
        Task { await findConnections() }
    }

    // MARK: Connections between themes

    /// A theme's color, the same in the graph and in lists. Buckets are grey.
    func themeColor(_ theme: String) -> Color {
        let names = projects.map(\.name)
        guard let i = names.firstIndex(of: theme) else { return .gray }
        return GraphStyle.color(index: i, of: names.count)
    }

    /// Sorted links in a theme that have not been checked for a second theme.
    var linksNeedingConnections: [String] {
        guard state.findConnections else { return [] }
        let names = Set(themes.map(\.name))
        return state.assignments.filter { names.contains($0.value.project) && $0.value.also == nil }.map(\.key).sorted()
    }

    /// Asks Claude, 60 links at a time, which other themes each link feeds.
    func findConnections() async {
        guard !Demo.isOn else { return }
        guard !isConnecting, !isSorting, !isDiscovering, themes.count > 1 else { return }
        let todo = linksNeedingConnections
        guard !todo.isEmpty else { return }
        isConnecting = true
        connectProgress = (0, todo.count)
        defer { isConnecting = false; scheduleSearchIndex() }
        let sorter = Sorter(backend: state.backend)
        let themes = self.themes
        for start in stride(from: 0, to: todo.count, by: 60) {
            guard state.findConnections else { return }
            let batch = Array(todo[start..<min(start + 60, todo.count)])
            let items = batch.compactMap { url -> (item: Sorter.Item, theme: String)? in
                guard let theme = state.assignments[url]?.project else { return nil }
                let tab = tabs.first { $0.url == url } ?? archive[url]?.asTab ?? SafariTab(url: url, title: "", lastViewed: nil)
                return (sortItem(tab), theme)
            }
            do {
                let found = try await sorter.connections(items, themes: themes)
                for (i, pair) in items.enumerated() {
                    state.assignments[pair.item.url]?.also = found[i] ?? []
                }
            } catch {
                return
            }
            connectProgress.done = min(start + batch.count, todo.count)
        }
    }
}
