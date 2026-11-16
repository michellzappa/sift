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

    /// The tab this pick shows in. Without a mode from the Mac: video is
    /// Watch, about 600 words or more is Read, the rest Scan.
    var readingMode: ReadingMode {
        if let mode, let m = ReadingMode(rawValue: mode) { return m }
        if vertical == true || verticalVideo != nil || Self.youTubeID(url) != nil { return .watch }
        return (content?.split(whereSeparator: \.isWhitespace).count ?? 0) >= 600 ? .read : .scan
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
    var goToLibrary: () -> Void

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
                                     kept: picks.filter { store.isKept($0.url) }.count, total: picks.count, library: goToLibrary)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id("end")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $position)
                .scrollIndicators(.hidden)
                .overlay {
                    if picks.isEmpty {
                        ContentUnavailableView("Nothing to watch", systemImage: "play.rectangle",
                                               description: Text(store.connectedFolder == nil
                                                                 ? "Connect the Sift folder: Lists, then Log. Today comes from your Mac."
                                                                 : "Videos from your feeds show here: YouTube channels and playlists, Shorts, TikTok."))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { store.sync() }
            .sheet(item: $browsing) { InAppBrowser(url: URL(string: $0.url)!).ignoresSafeArea() }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .sensoryFeedback(.success, trigger: burst)
            // Time on screen: from the card coming in to the card going out,
            // the tab closing or the app going to the background.
            .onAppear { startWatching() }
            .onDisappear { stopWatching() }
            .onChange(of: position) { _, _ in stopWatching(); startWatching() }
            .onChange(of: phase) { _, p in
                if p == .active { startWatching() } else { stopWatching() }
            }
        }
    }

    /// The URL of the card on screen. Before the first scroll the position
    /// is nil: the first card.
    private var current: String? { position ?? picks.first?.url }

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
        if let video = pick.verticalVideo {
            VerticalVideoCard(item: pick.item, video: video, active: current, doubleTap: keep,
                              played: { store.signal(.play, pick) }, text: open) { keepPill }
        } else {
            CardView(item: pick.item, tall: true, lede: true)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: keep)
                .onTapGesture(perform: open)
                .overlay(alignment: .bottomTrailing) { keepPill.padding(12) }
        }
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

/// The end of Today: what happened, when the next one comes, and the door
/// to the library. No more items load here.
private struct TodayEnd: View {
    let next: Date?
    let seen: Int
    let kept: Int
    let total: Int
    let library: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max").font(.system(size: 44)).foregroundStyle(.orange)
            Text("That's Today").font(.title2.weight(.semibold))
            Text("\(seen) of \(total) seen · \(kept) kept").font(.title3).foregroundStyle(.secondary)
            if let next {
                Text("The next one comes at \(next.formatted(date: .omitted, time: .shortened)).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer().frame(height: 16)
            Button("Go deeper in your library", action: library)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Scan and Read: today's headlines or long texts as a list. Tap opens the
/// reader and counts as seen; swipe right keeps, swipe left switches seen.
struct TodayListView: View {
    @Environment(Store.self) private var store
    let mode: ReadingMode
    @State private var reading: Item?

    private var picks: [TodayPick] { (store.today?.picks ?? []).filter { $0.readingMode == mode } }

    var body: some View {
        NavigationStack {
            List(picks) { pick in
                Button { open(pick) } label: { row(pick) }
                    .buttonStyle(.plain)
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
            .listStyle(.plain)
            .overlay {
                if picks.isEmpty {
                    ContentUnavailableView(mode == .scan ? "No headlines" : "Nothing to read", systemImage: mode.symbol,
                                           description: Text(store.connectedFolder == nil
                                                             ? "Connect the Sift folder: Lists, then Log. Today comes from your Mac."
                                                             : mode == .scan ? "Headlines and posts from your feeds show here: Hacker News, Reddit, Bluesky."
                                                                             : "Articles of about 3 minutes or more from your feeds show here."))
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { store.sync() }
            .sheet(item: $reading) { ReaderView(item: $0) }
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if kept {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    } else if !seen {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                    }
                    Text(pick.title)
                        .font(mode == .read ? .headline : .body)
                        .fontWeight(seen && !kept ? .regular : .semibold)
                        .foregroundStyle(seen && !kept ? .secondary : .primary)
                        .lineLimit(mode == .scan ? 3 : 2)
                }
                Text([pick.feedTitle, mode == .read ? pick.minutes.map { "\($0) min read" } : nil,
                      pick.date?.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if mode == .read, !pick.summary.isEmpty {
                    Text(pick.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
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
        }
        .padding(.vertical, mode == .scan ? 2 : 6)
        .contentShape(Rectangle())
    }
}
