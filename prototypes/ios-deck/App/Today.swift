import SwiftUI

// Today on the phone: the Mac writes iCloud Drive/Sift/Deck/today.json (the
// digest of offered items, Sift/Engine/Today.swift); the phone writes what
// it keeps to iCloud Drive/Sift/kept/iphone-<id>.json. Same shapes as the
// Mac's TodayPick and KeptItem, dates as ISO 8601.

struct TodayPick: Codable, Hashable, Sendable, Identifiable {
    var id: String { url }
    var url: String
    var title: String
    var date: Date?
    var feedID: String
    var feedTitle: String
    var summary: String
    var image: String?
    var reason: String
    var wildcard: Bool?
    /// The same link is in two or more of the user's feeds.
    var hot: Bool?
    /// The full text as Markdown, when the feed carries it.
    var content: String?
    /// True for a vertical video (the Mac sets it for YouTube Shorts).
    var vertical: Bool?
    /// "scan", "watch" or "read", from the Mac's classifier
    /// (Sift/Engine/Modes.swift). Older files have none: see `readingMode`.
    var mode: String?
    /// Top comments on a Hacker News or Reddit post, from the Mac
    /// (Sift/Feeds/Discussion.swift).
    var discussion: Discussion?
    /// The numbers that placed it (the Mac's `PickWhy`).
    var why: PickWhy?

    /// The tab this pick shows in. Without a mode from the Mac: video is
    /// Watch, headlines and posts are Scan, the rest Read.
    var readingMode: ReadingMode {
        if let mode, let m = ReadingMode(rawValue: mode) { return m }
        return ReadingMode.of(url: url, video: vertical == true || verticalVideo != nil || Self.youTubeID(url) != nil)
    }

    /// Minutes of reading at 220 words a minute, nil without text.
    var minutes: Int? {
        let words = content?.split(whereSeparator: \.isWhitespace).count ?? 0
        return words > 0 ? max(1, Int((Double(words) / 220).rounded())) : nil
    }

    /// The vertical video in this pick, if it is one.
    var verticalVideo: VerticalVideo? { VerticalVideo.detect(item, vertical: vertical) }

    /// The card's Item: the reason line takes the theme's place.
    var item: Item {
        let vid = Self.youTubeID(url)
        return Item(id: url, url: url, title: title, theme: reason.isEmpty ? feedTitle : reason, kind: vid == nil ? "article" : "video",
                    site: feedTitle, author: nil, saved: nil, duration: nil, summary: summary, passage: "",
                    transcript: "", text: content ?? "", image: image ?? vid.map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" },
                    also: [], neighbours: [], imageFile: nil,
                    video: vid.map { Item.Video(provider: "youtube", id: $0) },
                    published: date.map { $0.formatted(.iso8601) }, words: nil, keyLines: nil)
    }

    static func youTubeID(_ url: String) -> String? {
        guard let r = url.range(of: #"(?:v=|youtu\.be/|/shorts/)([\w-]{11})"#, options: .regularExpression) else { return nil }
        return String(url[r].suffix(11))
    }
}

/// Scan (headlines and posts), Watch (video) or Read (long text): the
/// phone's first three tabs, the same modes as the Mac's switch.
enum ReadingMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case scan, watch, read
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .scan: "list.bullet"
        case .watch: "play.rectangle"
        case .read: "book"
        }
    }
}

struct DiscussionComment: Codable, Hashable, Sendable {
    var author: String
    var text: String
}

struct Discussion: Codable, Hashable, Sendable {
    var url: String
    var site: String
    var count: Int?
    var comments: [DiscussionComment]
    var fetched: Date
}

/// The top comments under a Scan row: author and the first lines, quiet,
/// like a reply under a post.
struct DiscussionBlock: View {
    let discussion: Discussion
    var lines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(discussion.comments.enumerated()), id: \.offset) { _, c in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.35)).frame(width: 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.author).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(c.text).font(.footnote).foregroundStyle(.primary.opacity(0.85)).lineLimit(lines)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Text([discussion.site, discussion.count.map { "\($0) comments" }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}

struct TodayFile: Codable, Sendable {
    var schema: Int
    var slot: Date
    var next: Date
    var built: Date
    var picks: [TodayPick]
    var kept: [String]
}

struct KeptItem: Codable, Hashable, Sendable {
    var url: String
    var title: String
    var date: Date?
    var kept: Date
    var feedID: String?
    var feedTitle: String
    var summary: String
    var image: String?
}

/// Today: vertical cards, about ten. Swipe on = seen (an offered item you
/// pass is gone). Double-tap = keep (into your library on the Mac). Tap =
/// open: a video opens on its player and text, a page in Safari inside the app.
/// A vertical video plays inline in its card after a tap.
/// The time each card is on screen goes to the signals file (Signals.swift).
struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var browsing: Item?
    @State private var reading: Item?
    @State private var burst: String?
    /// The card on screen (its URL), from the scroll position.
    @State private var position: String?
    /// The pick being timed and when it came on screen.
    @State private var watching: (url: String, since: Date)?
    /// The Library part after Today: unseen saved videos, order fixed on open.
    @State private var library: [String] = []

    /// Watch: the videos among today's picks, as full-screen cards.
    private var picks: [TodayPick] { (store.today?.picks ?? []).filter { $0.readingMode == .watch } }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(picks.enumerated()), id: \.element.id) { i, pick in
                            TodayCard(pick: pick, number: i + 1, total: picks.count, burst: burst == pick.url,
                                      current: current == pick.url,
                                      open: { open(pick) }, keep: { keep(pick) })
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(pick.url)
                        }
                        if !picks.isEmpty {
                            TodayEnd(next: store.today?.next, seen: picks.filter { store.isSeen($0.url) }.count,
                                     kept: picks.filter { store.isKept($0.url) }.count, total: picks.count,
                                     library: savedVideos.count, mode: .watch)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id("end")
                        }
                        // From your Library: unseen saved videos, then the end.
                        let saved = savedVideos
                        ForEach(Array(saved.enumerated()), id: \.element.url) { i, item in
                            PlayableCard(item: item, active: current == item.url, reason: item.theme,
                                         played: { watched(item) }, text: { watched(item); reading = item }) {
                                if !store.isSeen(item.url) {
                                    Circle().fill(Color.accentColor).frame(width: 10, height: 10).padding(6)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                Label("Library \(i + 1)/\(saved.count)", systemImage: "books.vertical")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(10)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(item.url)
                        }
                        if !saved.isEmpty {
                            StreamEnd(mode: .watch)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id("library-end")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $position)
                .scrollIndicators(.hidden)
                .overlay {
                    if picks.isEmpty && savedVideos.isEmpty {
                        ContentUnavailableView("Nothing to watch", systemImage: "play.rectangle",
                                               description: Text(store.connectedFolder == nil
                                                                 ? "Connect the Sift folder: Themes, then Settings in the menu. Today comes from your Mac."
                                                                 : "Videos from your feeds show here: YouTube channels and playlists, Shorts, TikTok."))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { StreamMenu() } }
            .refreshable { store.sync() }
            .sheet(item: $browsing) { InAppBrowser(url: URL(string: $0.url)!).ignoresSafeArea() }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .sensoryFeedback(.success, trigger: burst)
            // Time on screen: from the card coming in to the card going out,
            // the tab closing or the app going to the background.
            .onAppear { startWatching(); fillLibrary() }
            .onChange(of: store.deck.items.count) { _, _ in fillLibrary() }
            .onDisappear { stopWatching() }
            .onChange(of: position) { _, _ in stopWatching(); startWatching() }
            .onChange(of: phase) { _, p in
                if p == .active { startWatching() } else { stopWatching() }
            }
        }
    }

    /// The URL of the card on screen. Before the first scroll the position
    /// is nil: the first card.
    private var current: String? { position ?? picks.first?.url ?? savedVideos.first?.url }

    private var savedVideos: [Item] {
        var byURL: [String: Item] = [:]
        for item in store.deck.items where item.readingMode == .watch { byURL[item.url] = byURL[item.url] ?? item }
        return library.compactMap { byURL[$0] }
    }

    /// Takes the queue once per open, so a card does not leave when watched.
    private func fillLibrary() {
        let fresh = store.libraryQueue(.watch, excluding: Set(picks.map(\.url)))
        let kept = library.filter { url in store.deck.items.contains { $0.url == url } }
        library = kept + fresh.filter { !kept.contains($0) }
    }

    /// Playing or opening a saved video counts as seen; scrolling past does not.
    private func watched(_ item: Item) {
        store.setSeen([item], true, mode: "library")
        store.record(item, .open, mode: "library", position: 0)
    }

    private func startWatching() {
        guard watching == nil, phase == .active, let url = current, picks.contains(where: { $0.url == url }) else { return }
        watching = (url, Date())
    }

    private func stopWatching() {
        guard let w = watching else { return }
        watching = nil
        guard let pick = picks.first(where: { $0.url == w.url }) else { return }
        store.signalShown(pick, seconds: Date().timeIntervalSince(w.since))
    }

    private func open(_ pick: TodayPick) {
        store.setSeen([pick.item], true, mode: "today")
        store.record(pick.item, .open, mode: "today", position: 0)
        store.signal(.open, pick)
        // The reader first, like Reeder: the full text (or the player and
        // summary), with "Open the original" at the end.
        reading = pick.item
        _ = browsing
    }

    private func keep(_ pick: TodayPick) {
        guard !store.isKept(pick.url) else { return }
        store.keep(pick)
        store.signal(.keep, pick)
        burst = pick.url
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { if burst == pick.url { burst = nil } }
    }
}

private struct TodayCard: View {
    @Environment(Store.self) private var store
    let pick: TodayPick
    let number: Int
    let total: Int
    let burst: Bool
    /// True while this card is the one on screen; a video stops when false.
    let current: Bool
    let open: () -> Void
    let keep: () -> Void
    @State private var shownAt: Date?

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                Text("\(number)/\(total)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
            .overlay {
                if burst {
                    Image(systemName: "star.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(.yellow)
                        .shadow(radius: 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: burst)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .onAppear { shownAt = Date() }
            .onDisappear {
                if let shownAt, Date().timeIntervalSince(shownAt) > 1 { store.setSeen([pick.item], true, mode: "today") }
                shownAt = nil
            }
    }

    /// A vertical video gets the full-card player layout; the rest the
    /// usual card. Both keep the Keep pill and double-tap = keep.
    @ViewBuilder private var content: some View {
        PlayableCard(item: pick.item, vertical: pick.vertical, active: current, reason: pick.reason,
                     doubleTap: keep, played: { store.signal(.play, pick) }, text: open) {
            HStack(spacing: 8) { notInterested; keepPill }
        }
        .overlay(alignment: .topLeading) { themeLabel.padding(10) }
    }

    /// The theme first, the network as a detail (issue #41).
    private var themeLabel: some View {
        HStack(spacing: 6) {
            if let theme = store.todayTheme(pick) {
                HStack(spacing: 5) {
                    Circle().fill(store.color(theme)).frame(width: 8, height: 8)
                    Text(theme).font(.caption.weight(.semibold)).lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            NetworkBadge(network: store.linkNetwork(of: pick), onImage: true)
        }
    }

    /// The three Not Interested choices of the Scan and Read rows (issue
    /// #46), sent to the Mac as a "less" request.
    private var notInterested: some View {
        Menu {
            Button("Less from \(pick.feedTitle)") { store.notInterested(pick, "source") }
            if let t = pick.why?.theme { Button("Less about \(t)") { store.notInterested(pick, "topic") } }
            Button("Seen Enough of This Story") { store.notInterested(pick, "story") }
        } label: {
            Image(systemName: "hand.thumbsdown")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
        }
        .accessibilityLabel("Not Interested")
    }

    private var keepPill: some View {
        let kept = store.isKept(pick.url)
        return Button(action: keep) {
            Label(kept ? "Kept" : "Keep", systemImage: kept ? "star.fill" : "star")
                .font(.caption.weight(.semibold))
                .foregroundStyle(kept ? Color.yellow : Color.primary)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The end of Today: what happened, when the next one comes, and how many
/// saved items follow.
private struct TodayEnd: View {
    let next: Date?
    let seen: Int
    let kept: Int
    let total: Int
    /// Unseen saved items that follow in this tab.
    let library: Int
    let mode: ReadingMode

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max").font(.system(size: 44)).foregroundStyle(.orange)
            Text("That's Today").font(.title2.weight(.semibold))
            Text("\(seen) of \(total) seen · \(kept) kept").font(.title3).foregroundStyle(.secondary)
            if let next {
                Text("The next one comes at \(next.formatted(date: .omitted, time: .shortened)).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if library > 0 {
                Spacer().frame(height: 8)
                Label("Next: \(library) from your Library", systemImage: "arrow.down")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The end of a mode tab: Today and your unseen saved items are done.
private struct StreamEnd: View {
    let mode: ReadingMode
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.tertiary)
            Text("You're through").font(.subheadline).foregroundStyle(.secondary)
            ThemesButton()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The quiet end of a stream: a short grey line and a standard button to the
/// Themes tab (owner, 2026-11-21: less contrast, a button for the link).
struct StreamFooter: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("You're through").font(.footnote).foregroundStyle(.tertiary)
            ThemesButton()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct ThemesButton: View {
    @Environment(Store.self) private var store
    var body: some View {
        Button { store.tabRequest = "themes" } label: { Label("Go to Themes", systemImage: "circle.hexagongrid") }
            .buttonStyle(.bordered).controlSize(.small).tint(.secondary)
    }
}

/// Scan and Read: today's headlines or long texts as a list. Tap opens the
/// reader and counts as seen; swipe right keeps, swipe left switches seen.
struct TodayListView: View {
    @Environment(Store.self) private var store
    let mode: ReadingMode
    /// Themes first (issue #41): sections per theme; off = one ranked list.
    @AppStorage("today.groupByTheme") private var groupByTheme = true
    @State private var reading: Item?
    @State private var past = ScrollPast()
    @State private var library: [String] = []
    @State private var trailFrom: Item?

    private var picks: [TodayPick] { groupByTheme ? sections.flatMap(\.items) : modePicks }
    private var modePicks: [TodayPick] { (store.today?.picks ?? []).filter { $0.readingMode == mode } }
    private var sections: [TodayThemes.Group<TodayPick>] { store.todaySections(modePicks) }

    private var saved: [Item] {
        var byURL: [String: Item] = [:]
        for item in store.deck.items where item.readingMode == mode { byURL[item.url] = byURL[item.url] ?? item }
        return library.compactMap { byURL[$0] }
    }

    var body: some View {
        NavigationStack {
            List {
                if !picks.isEmpty {
                    if groupByTheme {
                        let sections = sections
                        // Each section's first place in `picks`.
                        let starts = sections.indices.map { j in sections[..<j].reduce(0) { $0 + $1.items.count } }
                        ForEach(Array(sections.enumerated()), id: \.element.title) { j, section in
                            Section {
                                ForEach(Array(section.items.enumerated()), id: \.element.id) { k, pick in todayRow(pick, starts[j] + k) }
                            } header: {
                                ThemeSectionHeader(title: section.title, color: section.theme.map { store.color($0) } ?? .secondary)
                            } footer: {
                                // Scan has no saved part, so its end sits under Today.
                                if mode == .scan, j == sections.count - 1 { StreamFooter() }
                            }
                        }
                    } else {
                        Section {
                            ForEach(Array(picks.enumerated()), id: \.element.id) { i, pick in todayRow(pick, i) }
                        } header: { Text("Today") } footer: {
                            // Scan has no saved part, so its end sits under Today.
                            if mode == .scan { StreamFooter() }
                        }
                    }
                }
                let saved = saved
                // Scan is browsing, never saving (owner, 2026-11-21: "scan means
                // I'm not saving, just browsing"): no saved items in Scan.
                if mode != .scan, !saved.isEmpty {
                    Section {
                        ForEach(Array(saved.enumerated()), id: \.element.url) { i, item in
                            Button { openSaved(item) } label: { LibraryRow(item: item, mode: mode) }
                                .buttonStyle(.plain)
                                .contextMenu { Button { trailFrom = item } label: { Label("More Like This", systemImage: "point.topleft.down.to.point.bottomright.curvepath") } }
                                .onAppear { if mode == .scan { past.appear(item.url, at: picks.count + i) } }
                                .onDisappear {
                                    guard mode == .scan else { return }
                                    past.disappear(item.url, at: picks.count + i) { url in
                                        if let it = saved.first(where: { $0.url == url }), !store.isSeen(url) {
                                            store.setSeen([it], true, mode: "scan")
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    let seen = store.isSeen(item.url)
                                    Button { store.setSeen([item], !seen, mode: "library") } label: {
                                        Label(seen ? "Unseen" : "Seen", systemImage: seen ? "circle.fill" : "checkmark.circle")
                                    }
                                    .tint(.accentColor)
                                }
                        }
                    } header: { Text("From your Library") } footer: {
                        StreamFooter()
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if picks.isEmpty && saved.isEmpty {
                    ContentUnavailableView(mode == .scan ? "No headlines" : "Nothing to read", systemImage: mode.symbol,
                                           description: Text(store.connectedFolder == nil
                                                             ? "Connect the Sift folder: Themes, then Settings in the menu. Today comes from your Mac."
                                                             : mode == .scan ? "Headlines and posts from your feeds show here: Hacker News, Reddit, Bluesky."
                                                                             : "Articles of about 3 minutes or more from your feeds show here."))
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { StreamMenu() } }
            .refreshable { store.sync() }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .background { Color.clear.sheet(item: $trailFrom) { TrailSheet(seed: $0) } }
            .onAppear { past.active = true; fillLibrary() }
            .onDisappear { past.active = false }
            .onChange(of: store.deck.items.count) { _, _ in fillLibrary() }
        }
    }

    private func fillLibrary() {
        let fresh = store.libraryQueue(mode, excluding: Set(picks.map(\.url)))
        let kept = library.filter { url in store.deck.items.contains { $0.url == url } }
        library = kept + fresh.filter { !kept.contains($0) }
    }

    private func openSaved(_ item: Item) {
        store.setSeen([item], true, mode: "library")
        store.record(item, .open, mode: "library", position: 0)
        reading = item
    }

    /// One Today row. `i` is its place in `picks`, for Scan's scrolled-past rule.
    private func todayRow(_ pick: TodayPick, _ i: Int) -> some View {
                Button { open(pick) } label: { row(pick) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { trailFrom = store.trailNode(pick).item } label: { Label("More Like This", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                        Menu {
                            Button("Less from \(pick.feedTitle)") { store.notInterested(pick, "source") }
                            if let t = pick.why?.theme { Button("Less about \(t)") { store.notInterested(pick, "topic") } }
                            Button("Seen Enough of This Story") { store.notInterested(pick, "story") }
                        } label: { Label("Not Interested", systemImage: "hand.thumbsdown") }
                    }
                    // Scan: a headline scrolled past counts as seen.
                    .onAppear { if mode == .scan { past.appear(pick.url, at: i) } }
                    .onDisappear {
                        guard mode == .scan else { return }
                        past.disappear(pick.url, at: i) { url in
                            if let p = picks.first(where: { $0.url == url }), !store.isSeen(url) {
                                store.setSeen([p.item], true, mode: "scan")
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !store.isKept(pick.url) {
                            Button { store.keep(pick); store.signal(.keep, pick) } label: { Label("Keep", systemImage: "star") }
                                .tint(.yellow)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        let seen = store.isSeen(pick.url)
                        Button { store.setSeen([pick.item], !seen, mode: "today") } label: {
                            Label(seen ? "Unseen" : "Seen", systemImage: seen ? "circle.fill" : "checkmark.circle")
                        }
                        .tint(.accentColor)
                    }
    }

    private func open(_ pick: TodayPick) {
        store.setSeen([pick.item], true, mode: "today")
        store.record(pick.item, .open, mode: "today", position: 0)
        store.signal(.open, pick)
        reading = pick.item
    }

    @ViewBuilder
    private func row(_ pick: TodayPick) -> some View {
        let seen = store.isSeen(pick.url)
        let kept = store.isKept(pick.url)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pick.title)
                    .font(mode == .read ? .headline : .body)
                    .fontWeight(seen && !kept ? .regular : .semibold)
                    .foregroundStyle(seen && !kept ? .secondary : .primary)
                    .lineLimit(mode == .scan ? 3 : 2)
                HStack(spacing: 6) {
                    NetworkBadge(network: store.linkNetwork(of: pick))
                    Text([pick.feedTitle, mode == .read ? pick.minutes.map { "\($0) min read" } : nil,
                          pick.date?.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if mode == .read, !pick.summary.isEmpty {
                    Text(pick.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
                if let d = pick.discussion, !d.comments.isEmpty {
                    DiscussionBlock(discussion: d)
                }
            }
            Spacer(minLength: 0)
            if mode == .read, let image = pick.image, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { Color.secondary.opacity(0.12) }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .saturation(seen && !kept ? 0 : 1)
            }
            RowMark(seen: seen, kept: kept)
        }
        .padding(.vertical, mode == .scan ? 2 : 6)
        .contentShape(Rectangle())
    }
}

/// Today, themes first (issue #41): the theme and network of each pick, the
/// same rules as the Mac (Sift/App/AppModel+TodayThemes.swift).
extension Store {
    /// The theme Today fitted the pick to, else the top theme of the Your
    /// Graph creator its feed comes from (creators.json).
    func todayTheme(_ pick: TodayPick) -> String? { todaySections([pick]).first?.theme }

    func todaySections(_ picks: [TodayPick]) -> [TodayThemes.Group<TodayPick>] {
        let creatorTheme = Dictionary((creators?.creators ?? []).compactMap { r in
            r.feedID.flatMap { id in r.themes.max { $0.value < $1.value }.map { (id, $0.key) } }
        }, uniquingKeysWith: { a, _ in a })
        let names = Set(deck.themes.map(\.name))
        func known(_ t: String?) -> String? { t.flatMap { names.isEmpty || names.contains($0) ? $0 : nil } }
        return TodayThemes.group(picks, theme: { known($0.why?.theme) ?? known(creatorTheme[$0.feedID]) }, score: { $0.why?.score })
    }

    /// The network badge: the link's host, else its feed's provider.
    func linkNetwork(of pick: TodayPick) -> LinkNetwork {
        LinkNetwork.of(url: pick.url, provider: macFeeds?.feeds.first { $0.id == pick.feedID }?.provider)
    }
}
