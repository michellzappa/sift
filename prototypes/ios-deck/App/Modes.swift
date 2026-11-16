import SwiftUI

// Scan, Watch, Read: the phone's first split, for Today (what your feeds
// offer) and your Library (what you saved). The Mac sets each Today pick's
// mode (Sift/Engine/Modes.swift); saved items and older files use `of`.

extension ReadingMode {
    /// Video is Watch; headline sites and posts are Scan; the rest Read.
    static func of(url: String, video: Bool) -> ReadingMode {
        if video { return .watch }
        let host = URL(string: url)?.host()?.lowercased() ?? ""
        let headline = ["x.com", "bsky.app", "news.ycombinator.com", "lobste.rs", "news.google.com"].contains(host)
            || host.hasSuffix("reddit.com") || host.hasSuffix("twitter.com") || host.hasSuffix("instagram.com")
            || host.hasSuffix("threads.net")
        return headline ? .scan : .read
    }
}

extension Item {
    var readingMode: ReadingMode {
        ReadingMode.of(url: url, video: isVideo || video != nil || VerticalVideo.detect(self, vertical: nil) != nil)
    }
}

/// Today or Library inside a mode tab.
enum ModePart: String, CaseIterable, Identifiable {
    case today, library
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The Today / Library switch at the top of a mode tab.
struct PartPicker: View {
    @Binding var part: ModePart
    var body: some View {
        Picker("Show", selection: $part) {
            ForEach(ModePart.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// One mode tab: Today's picks or your saved items in that mode.
struct ModeTab: View {
    let mode: ReadingMode
    @State private var part: ModePart = .today

    var body: some View {
        switch (part, mode) {
        case (.today, .watch): TodayView(part: $part)
        case (.today, _): TodayListView(mode: mode, part: $part)
        case (.library, _): LibraryModeList(mode: mode, part: $part)
        }
    }
}

/// Your saved items in one mode, unseen first. Tap opens the reader (a
/// video on its player) and counts as seen; swipe switches seen. In Scan a
/// row scrolled past counts as seen.
struct LibraryModeList: View {
    @Environment(Store.self) private var store
    let mode: ReadingMode
    @Binding var part: ModePart
    @State private var reading: Item?
    @State private var past = ScrollPast()

    private var items: [Item] {
        let all = store.deck.items.filter { $0.readingMode == mode }
        return all.filter { !store.isSeen($0.url) } + all.filter { store.isSeen($0.url) }
    }

    var body: some View {
        NavigationStack {
            let items = items
            List(Array(items.enumerated()), id: \.element.id) { i, item in
                Button { open(item) } label: { row(item) }
                    .buttonStyle(.plain)
                    .onAppear { if mode == .scan { past.appear(item.url, at: i) } }
                    .onDisappear {
                        guard mode == .scan else { return }
                        past.disappear(item.url, at: i) { url in
                            if let it = items.first(where: { $0.url == url }), !store.isSeen(url) {
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
            .listStyle(.plain)
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Nothing saved here", systemImage: mode.symbol,
                                           description: Text(store.deck.items.isEmpty
                                                             ? "Import your library: Lists, then Log."
                                                             : "Your saved \(mode == .watch ? "videos" : mode == .read ? "articles" : "posts and headlines") show here."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { PartPicker(part: $part) } }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .onAppear { past.active = true }
            .onDisappear { past.active = false }
        }
    }

    private func open(_ item: Item) {
        store.setSeen([item], true, mode: "library")
        store.record(item, .open, mode: "library", position: 0)
        reading = item
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        let seen = store.isSeen(item.url)
        if mode == .watch {
            VStack(alignment: .leading, spacing: 6) {
                ItemImage(item: item, height: 190)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .saturation(seen ? 0 : 1)
                title(item, seen)
                meta(item)
            }
            .padding(.vertical, 6)
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    title(item, seen)
                    meta(item)
                    if mode == .read, !item.summary.isEmpty {
                        Text(item.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                if mode == .read {
                    ItemImage(item: item, height: 72).frame(width: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .saturation(seen ? 0 : 1)
                }
            }
            .padding(.vertical, mode == .scan ? 2 : 6)
            .contentShape(Rectangle())
        }
    }

    /// The title, then the unseen dot.
    private func title(_ item: Item, _ seen: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(item.title)
                .font(mode == .read ? .headline : .body)
                .fontWeight(seen ? .regular : .semibold)
                .foregroundStyle(seen ? .secondary : .primary)
                .lineLimit(mode == .scan ? 3 : 2)
            if !seen { Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(.top, 7) }
        }
    }

    private func meta(_ item: Item) -> some View {
        Text([item.site, item.theme, item.readTime].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
}
