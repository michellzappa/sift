import Foundation
import HouseKit

// MARK: - Command palette items (⌘K, Views/CommandPalette.swift)
//
// The palette lists sidebar places, Settings panes, actions, a Follow
// item for a typed handle or address, and links. This file makes the
// items and ranks them. The view runs the chosen item.

/// One row in the palette.
struct PaletteItem: Identifiable, Hashable {
    enum Section: String, CaseIterable {
        case follow = "Follow"
        case recent = "Recent"
        case goTo = "Go to"
        case settings = "Settings"
        case actions = "Actions"
        case links = "Links"
        case text = "In your library"
        case today = "Today"
    }

    /// What Return does.
    enum Command: Hashable {
        case go(SidebarItem)
        case settings(String)
        case followSheet
        case follow(String)
        case reload
        case checkFeeds
        case newToday
        case discover
        case sort
        case export(String)
        case updates
        case versionHistory
        case setupGuide
        /// Show the link's list, then open the link in Safari.
        case link(url: String, list: SidebarItem)
    }

    /// Stable across rebuilds: the recent list stores it.
    var key: String
    var section: Section
    var title: String
    var detail = ""
    var symbol: String
    /// Right-aligned: the kind of place or the keyboard shortcut.
    var hint = ""
    var command: Command
    /// Rank inside a search. Higher is better.
    var score = 0

    var id: String { section.rawValue + "|" + key }
}

/// A group of rows under one header.
struct PaletteSection: Identifiable {
    var section: PaletteItem.Section
    var items: [PaletteItem]
    var id: String { section.rawValue }
}

/// Settings pane selection that the palette can set from outside the
/// Settings window. SettingsView holds this one instance.
@MainActor
enum SettingsRoute {
    static let navigation = SettingsNavigation(selection: Demo.settingsTab ?? SettingsPane.generalID)

    /// The panes, in SettingsView order: id, title, symbol.
    static let panes: [(id: String, title: String, symbol: String)] = [
        ("general", "General", "gearshape"),
        ("inputs", "Inputs", "tray.and.arrow.down"),
        ("library", "Library", "books.vertical"),
        ("outputs", "Outputs", "tray.and.arrow.up"),
        ("intelligence", "Intelligence", "sparkles"),
        ("themes", "Themes", "circle.hexagongrid"),
        ("telemetry", "Telemetry", "chart.bar.xaxis"),
        ("about", "About", "info.circle"),
    ]
}

/// The last places opened from the palette, newest first (UserDefaults).
enum PaletteRecents {
    private static let defaultsKey = "palette.recent"
    static let limit = 8

    static var keys: [String] { UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [] }

    static func add(_ key: String) {
        var list = keys.filter { $0 != key }
        list.insert(key, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: defaultsKey)
    }
}

enum PaletteRanking {
    /// Fuzzy match: every query character in order (spaces ignored). Word
    /// starts, runs of adjacent characters and a matching prefix score
    /// higher; long text scores a little lower. Nil when it does not match.
    static func score(_ query: String, _ text: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return 0 }
        let lowered = text.lowercased()
        let t = Array(lowered)
        var qi = 0
        var last = -2
        var score = 0
        for (i, c) in t.enumerated() where qi < q.count {
            guard c == q[qi] else { continue }
            var s = 1
            if i == 0 || !(t[i - 1].isLetter || t[i - 1].isNumber) { s += 8 }
            if i == last + 1 { s += 5 }
            score += s
            last = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        let whole = query.lowercased().trimmingCharacters(in: .whitespaces)
        if lowered.hasPrefix(whole) { score += 30 } else if lowered.contains(whole) { score += 12 }
        return score - min(t.count / 8, 10)
    }

    /// The items that match, with their score, best first.
    static func rank(_ items: [PaletteItem], _ query: String) -> [PaletteItem] {
        items.compactMap { item in
            let main = score(query, item.title)
            let side = item.detail.isEmpty ? nil : score(query, item.detail).map { $0 / 3 }
            guard let best = [main, side].compactMap({ $0 }).max() else { return nil }
            var ranked = item
            ranked.score = best
            return ranked
        }
        .sorted { $0.score > $1.score }
    }
}

@MainActor
enum PaletteCatalog {
    // MARK: Places

    /// Every sidebar place, in sidebar order.
    static func places(_ model: AppModel) -> [PaletteItem] {
        var out: [PaletteItem] = []
        func add(_ key: String, _ title: String, _ symbol: String, _ hint: String, _ item: SidebarItem, detail: String = "") {
            out.append(PaletteItem(key: "go:" + key, section: .goTo, title: title, detail: detail, symbol: symbol, hint: hint, command: .go(item)))
        }
        if !model.state.feeds.isEmpty { add("today", "Today", "sun.max", "Feeds", .today) }
        add("overview", "Overview", "circle.hexagongrid", "Library", .overview)
        for (id, symbol) in sourceIDs(model) {
            add("source:" + id, model.sourceTitle(id), symbol, "Source", .source(id))
        }
        add("unsorted", "Unsorted", "tray", "Library", .unsorted)
        add("archive", "Archive", "archivebox", "Library", .archive)
        if !model.transcriptTabs.isEmpty { add("transcripts", "Transcripts", "captions.bubble", "Library", .transcripts) }
        if !model.duplicateTabs.isEmpty { add("duplicates", "Duplicates", "square.on.square", "Library", .duplicates) }
        if !model.brokenTabs.isEmpty { add("broken", "Broken Links", "link.badge.plus", "Library", .broken) }
        if !model.isSavedList { add("close", "To Close", "xmark.square", "Library", .closeQueue) }
        for theme in model.projects {
            add("theme:" + theme.name, theme.name, "circle.hexagongrid.circle", "Theme", .project(theme.name))
        }
        for bucket in Project.buckets {
            add("theme:" + bucket, Project.displayName(bucket), "tray.2", "Outside themes", .project(bucket))
        }
        for folder in model.feedFolders {
            add("folder:" + folder, folder, "folder", "Folder", .feedFolder(folder))
        }
        for feed in model.state.feeds.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            let symbol = FeedProviders.provider(id: feed.provider)?.symbol ?? "dot.radiowaves.up.forward"
            add("feed:" + feed.id, feed.title, symbol, "Feed", .feed(feed.id), detail: feed.category ?? "")
        }
        for query in model.state.savedSearches {
            add("saved:" + query, query, "magnifyingglass", "Saved search", .saved(query))
        }
        for d in model.destinations {
            add("sent:" + d.id, d.name, d.symbol, "Sent to", .destination(d.id), detail: d.detail)
        }
        return out
    }

    /// The source rows of the sidebar's Library section: id and symbol.
    private static func sourceIDs(_ model: AppModel) -> [(String, String)] {
        var out: [(String, String)] = []
        for d in model.devices where d.tabCount > 0 { out.append((d.id, "safari")) }
        for p in model.chromeProfiles { out.append((p.id, "globe")) }
        if model.readingListCount > 0 { out.append((ReadingListReader.sourceID, "eyeglasses")) }
        if model.instagramCount > 0 { out.append((InstagramReader.sourceID, "camera")) }
        if model.tiktokCount > 0 { out.append((TikTokReader.sourceID, "music.note")) }
        if model.xConnected { out.append((AppModel.xBookmarksSourceID, "bookmark")) }
        if !model.state.kept.isEmpty { out.append((TodayStore.keptSourceID, "star")) }
        for i in model.state.importedSources { out.append((LinkImporter.sourcePrefix + i.id, "tray.and.arrow.down")) }
        return out
    }

    static func settings() -> [PaletteItem] {
        SettingsRoute.panes.map {
            PaletteItem(key: "settings:" + $0.id, section: .settings, title: "\($0.title) Settings", symbol: $0.symbol, hint: "Settings", command: .settings($0.id))
        }
    }

    // MARK: Actions

    /// Actions. Demo mode leaves out the ones that use the network.
    static func actions(_ model: AppModel) -> [PaletteItem] {
        var out: [PaletteItem] = []
        func add(_ key: String, _ title: String, _ symbol: String, _ hint: String, _ command: PaletteItem.Command) {
            out.append(PaletteItem(key: "action:" + key, section: .actions, title: title, symbol: symbol, hint: hint, command: command))
        }
        let online = !Demo.isOn
        if online { add("follow", "Follow…", "plus", "⇧⌘N", .followSheet) }
        add("reload", "Reload", "arrow.clockwise", "⌘R", .reload)
        if online, !model.state.feeds.isEmpty { add("feeds", "Check Feeds", "dot.radiowaves.up.forward", "Action", .checkFeeds) }
        if !model.state.feeds.isEmpty { add("today", "New Today Digest", "sun.max", "Action", .newToday) }
        if online, !model.isDiscovering, !model.isSorting {
            add("discover", "Discover Themes", "circle.hexagongrid.circle", "Action", .discover)
            if !model.themes.isEmpty, model.unsortedCount > 0 { add("sort", "Sort into Themes", "sparkles", "Action", .sort) }
        }
        for e in Exporters.all { add("export:" + e.id, "Export \(e.name)", "square.and.arrow.up", "Export", .export(e.id)) }
        if online { add("updates", "Check for Updates", "arrow.down.circle", "Action", .updates) }
        add("history", "Version History", "clock.arrow.circlepath", "Action", .versionHistory)
        add("guide", "Setup Guide", "questionmark.circle", "Action", .setupGuide)
        return out
    }

    /// "Follow <text>" when the text is a handle or address a feed
    /// provider knows (no network: `matches` only).
    static func follow(_ text: String) -> PaletteItem? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Demo.isOn, !s.isEmpty else { return nil }
        guard let provider = FeedProviders.all.first(where: { $0.matches(s) }) else { return nil }
        // A plain web address has no spaces.
        if provider.id == WebProvider.id, s.contains(where: \.isWhitespace) { return nil }
        return PaletteItem(key: "follow:" + s, section: .follow, title: "Follow \(s)", detail: provider.name,
                           symbol: provider.symbol, hint: "Follow", command: .follow(s), score: .max)
    }

    // MARK: Links

    /// The list a link lives in: its theme, the archive, or the overview.
    static func list(for url: String, _ model: AppModel) -> SidebarItem {
        if let project = model.state.assignments[url]?.project { return .project(project) }
        if model.archive[url]?.isArchived == true { return .archive }
        return .overview
    }

    static func title(of tab: SafariTab, _ model: AppModel) -> String {
        tab.hasUsefulTitle ? tab.title : title(of: tab.url, model)
    }

    /// The preview's title, or the address when there is none.
    static func title(of url: String, _ model: AppModel) -> String {
        if let t = model.previews[url]?.title, !t.isEmpty { return t }
        return url
    }

    /// Open and archived links whose title matches, best first.
    static func links(_ query: String, _ model: AppModel, limit: Int = 8) -> [PaletteItem] {
        var seen = Set<String>()
        var items: [PaletteItem] = []
        for tab in model.tabs + model.archivedTabs where seen.insert(tab.url).inserted {
            let theme = model.state.assignments[tab.url]?.project
            items.append(PaletteItem(key: "link:" + tab.url, section: .links, title: title(of: tab, model), detail: tab.host,
                                     symbol: "link", hint: theme.map(Project.displayName) ?? "Link",
                                     command: .link(url: tab.url, list: list(for: tab.url, model))))
        }
        return Array(PaletteRanking.rank(items, query).prefix(limit))
    }

    /// Today's feed picks whose title matches.
    static func todayPicks(_ query: String, _ model: AppModel, limit: Int = 5) -> [PaletteItem] {
        let items = model.todayPicks.map {
            PaletteItem(key: "pick:" + $0.url, section: .today, title: $0.title, detail: $0.feedTitle,
                        symbol: "sun.max", hint: "Today", command: .link(url: $0.url, list: .today))
        }
        return Array(PaletteRanking.rank(items, query).prefix(limit))
    }

    /// Full-text hits from search.sqlite, without the links already listed.
    static func textHits(_ hits: [SearchIndex.Hit], excluding: Set<String>, _ model: AppModel, limit: Int = 8) -> [PaletteItem] {
        var titles: [String: String] = [:]
        for tab in model.archivedTabs + model.tabs { titles[tab.url] = title(of: tab, model) }
        var out: [PaletteItem] = []
        for hit in hits where !excluding.contains(hit.url) {
            let name = titles[hit.url] ?? title(of: hit.url, model)
            let theme = model.state.assignments[hit.url]?.project
            out.append(PaletteItem(key: "text:" + hit.url, section: .text, title: name,
                                   detail: hit.snippet.replacingOccurrences(of: "\n", with: " "),
                                   symbol: "doc.text.magnifyingglass", hint: theme.map(Project.displayName) ?? "Text",
                                   command: .link(url: hit.url, list: list(for: hit.url, model)),
                                   score: 0))
            if out.count == limit { break }
        }
        return out
    }

    // MARK: Results

    /// The rows for a query. An empty query shows recent places, then
    /// every place. Otherwise each section is ranked, and the section with
    /// the best match comes first.
    static func results(_ query: String, hits: [SearchIndex.Hit], _ model: AppModel) -> [PaletteSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let places = places(model)
        let fixed = places + settings() + actions(model)
        if q.isEmpty {
            let byKey = Dictionary(fixed.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            let recent = PaletteRecents.keys.compactMap { byKey[$0] }.map { var r = $0; r.section = .recent; return r }
            return [PaletteSection(section: .recent, items: recent), PaletteSection(section: .goTo, items: places)]
                .filter { !$0.items.isEmpty }
        }
        var sections: [PaletteSection] = []
        if let follow = follow(q) { sections.append(PaletteSection(section: .follow, items: [follow])) }
        sections.append(PaletteSection(section: .goTo, items: Array(PaletteRanking.rank(places, q).prefix(8))))
        sections.append(PaletteSection(section: .settings, items: Array(PaletteRanking.rank(settings(), q).prefix(4))))
        sections.append(PaletteSection(section: .actions, items: Array(PaletteRanking.rank(actions(model), q).prefix(6))))
        if q.count >= 2 {
            let links = links(q, model)
            sections.append(PaletteSection(section: .links, items: links))
            sections.append(PaletteSection(section: .today, items: todayPicks(q, model)))
            let listed = Set(links.compactMap { if case .link(let url, _) = $0.command { url } else { nil } })
            sections.append(PaletteSection(section: .text, items: textHits(hits, excluding: listed, model)))
        }
        // Full-text hits have no fuzzy score: they keep their place after
        // the ranked sections.
        let ranked = sections.filter { !$0.items.isEmpty && $0.section != .text }
            .sorted { ($0.items.first?.score ?? 0) > ($1.items.first?.score ?? 0) }
        return ranked + sections.filter { $0.section == .text && !$0.items.isEmpty }
    }
}
