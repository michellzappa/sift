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

extension Store {
    /// Your unseen saved items in one mode, for the Library part of a mode
    /// tab, without the links Today already shows. Watch: playable ones
    /// first. The views keep this order while open, so a row or card does
    /// not move or vanish when it becomes seen.
    func libraryQueue(_ mode: ReadingMode, excluding: Set<String>) -> [String] {
        var seenURL = excluding
        let items = deck.items.filter { $0.readingMode == mode && !isSeen($0.url) && seenURL.insert($0.url).inserted }
        guard mode == .watch else { return items.map(\.url) }
        return (items.filter { $0.playable != nil } + items.filter { $0.playable == nil }).map(\.url)
    }
}

/// One mode tab (owner, 2026-11-17: no Today / Library switch): one stream
/// that ends. Today's picks in this mode first, then "From your Library",
/// your unseen saved items in this mode. Themes is where you browse the
/// library on purpose.
struct ModeTab: View {
    let mode: ReadingMode

    var body: some View {
        if mode == .watch { TodayView() } else { TodayListView(mode: mode) }
    }
}

/// A saved item as a row in Scan or Read, unseen dot after the title.
struct LibraryRow: View {
    @Environment(Store.self) private var store
    let item: Item
    let mode: ReadingMode

    var body: some View {
        let seen = store.isSeen(item.url)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(mode == .read ? .headline : .body)
                    .fontWeight(seen ? .regular : .semibold)
                    .foregroundStyle(seen ? .secondary : .primary)
                    .lineLimit(mode == .scan ? 3 : 2)
                Text([item.site, item.theme, item.readTime].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            RowMark(seen: seen)
        }
        .padding(.vertical, mode == .scan ? 2 : 6)
        .contentShape(Rectangle())
    }
}

/// The unseen dot (or the kept star) in a fixed column at the right edge of
/// a row, always in the same place (owner, 2026-11-21: "rightmost in row
/// always"). The column stays when seen, so the text never moves.
struct RowMark: View {
    let seen: Bool
    var kept = false

    var body: some View {
        ZStack {
            if kept {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
            } else if !seen {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
            }
        }
        .frame(width: 12, height: 12)
        .padding(.top, 5)
    }
}
