import SwiftUI

extension Item {
    /// The video a card can play: vertical (Shorts, Instagram, TikTok) or a
    /// wide YouTube video. Nil: Sift has no player for it.
    var playable: (video: VerticalVideo, wide: Bool)? {
        if let v = VerticalVideo.detect(self) { return (v, false) }
        if let id = TodayPick.youTubeID(url) { return (.youTube(id), true) }
        if let video, video.provider == "youtube" { return (.youTube(video.id), true) }
        return nil
    }
}

/// Library in the Watch tab (owner, 2026-11-16: "always have video"): your
/// saved videos as full cards with the player, like Today's Watch. YouTube
/// plays muted while on screen; Instagram and TikTok play on a tap. Unseen
/// first, in an order fixed when the tab opens, so a card does not jump
/// when it becomes seen. Playing or opening the text counts as seen;
/// scrolling past does not (a saved link stays until you watch it).
struct LibraryWatchView: View {
    @Environment(Store.self) private var store
    @Binding var part: ModePart
    @State private var position: String?
    @State private var reading: Item?
    @State private var order: [String] = []

    private var items: [Item] {
        var byURL: [String: Item] = [:]
        for item in store.deck.items where item.readingMode == .watch { byURL[item.url] = byURL[item.url] ?? item }
        return order.compactMap { byURL[$0] }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let items = items
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.url) { i, item in
                            card(item, current: (position ?? items.first?.url) == item.url)
                                .overlay(alignment: .topTrailing) {
                                    Text("\(i + 1)/\(items.count)")
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
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $position)
                .scrollIndicators(.hidden)
                .overlay {
                    if items.isEmpty {
                        ContentUnavailableView("No saved videos", systemImage: "play.rectangle",
                                               description: Text(store.deck.items.isEmpty
                                                                 ? "Import your library: Lists, then Log."
                                                                 : "Videos you save show here: YouTube, Instagram reels, TikTok."))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { PartPicker(part: $part) } }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .onAppear(perform: sortOnce)
            .onChange(of: store.deck.items.count) { _, _ in sortOnce() }
        }
    }

    @ViewBuilder
    private func card(_ item: Item, current: Bool) -> some View {
        if let p = item.playable {
            VerticalVideoCard(item: item, video: p.video, active: current,
                              played: { watched(item) }, text: { open(item) },
                              wide: p.wide, autoplay: true) { seenDot(item) }
        } else {
            CardView(item: item, tall: true)
                .contentShape(Rectangle())
                .onTapGesture { open(item) }
        }
    }

    @ViewBuilder
    private func seenDot(_ item: Item) -> some View {
        if !store.isSeen(item.url) {
            Circle().fill(Color.accentColor).frame(width: 10, height: 10).padding(6)
        }
    }

    private func sortOnce() {
        var seen = Set<String>()
        let all = store.deck.items.filter { $0.readingMode == .watch && seen.insert($0.url).inserted }
        // Playable first, then unseen first.
        let ranked = all.sorted { a, b in
            let pa = a.playable != nil, pb = b.playable != nil
            if pa != pb { return pa }
            return !store.isSeen(a.url) && store.isSeen(b.url)
        }
        order = ranked.map(\.url)
    }

    private func watched(_ item: Item) {
        store.setSeen([item], true, mode: "library")
        store.record(item, .open, mode: "library", position: 0)
    }

    private func open(_ item: Item) {
        watched(item)
        reading = item
    }
}
