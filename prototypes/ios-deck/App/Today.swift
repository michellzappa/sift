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
    /// The full text as Markdown, when the feed carries it.
    var content: String?

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
struct TodayView: View {
    @Environment(Store.self) private var store
    @State private var browsing: Item?
    @State private var reading: Item?
    @State private var burst: String?
    var goToLibrary: () -> Void

    private var picks: [TodayPick] { store.today?.picks ?? [] }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(picks.enumerated()), id: \.element.id) { i, pick in
                            TodayCard(pick: pick, number: i + 1, total: picks.count, burst: burst == pick.url,
                                      open: { open(pick) }, keep: { keep(pick) })
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                        if !picks.isEmpty {
                            TodayEnd(next: store.today?.next, seen: picks.filter { store.isSeen($0.url) }.count,
                                     kept: picks.filter { store.isKept($0.url) }.count, total: picks.count, library: goToLibrary)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollIndicators(.hidden)
                .overlay {
                    if picks.isEmpty {
                        ContentUnavailableView("Nothing in Today yet", systemImage: "sun.max",
                                               description: Text(store.connectedFolder == nil
                                                                 ? "Connect the Sift folder in Log. Today comes from your Mac, at 07:00 and 17:00."
                                                                 : "Follow feeds in Sift on your Mac: Settings > Inputs > Feeds."))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { store.sync() }
            .sheet(item: $browsing) { InAppBrowser(url: URL(string: $0.url)!).ignoresSafeArea() }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .sensoryFeedback(.success, trigger: burst)
        }
    }

    private func open(_ pick: TodayPick) {
        store.setSeen([pick.item], true, mode: "today")
        store.record(pick.item, .open, mode: "today", position: 0)
        // The reader first, like Reeder: the full text (or the player and
        // summary), with "Open the original" at the end.
        reading = pick.item
        _ = browsing
    }

    private func keep(_ pick: TodayPick) {
        guard !store.isKept(pick.url) else { return }
        store.keep(pick)
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
    let open: () -> Void
    let keep: () -> Void
    @State private var shownAt: Date?

    var body: some View {
        let kept = store.isKept(pick.url)
        CardView(item: pick.item, tall: true, lede: true)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: keep)
            .onTapGesture(perform: open)
            .overlay(alignment: .topTrailing) {
                Text("\(number)/\(total)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: keep) {
                    Label(kept ? "Kept" : "Keep", systemImage: kept ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kept ? Color.yellow : Color.primary)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(12)
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
