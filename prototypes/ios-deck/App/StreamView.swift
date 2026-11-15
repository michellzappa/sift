import SwiftUI

/// The deep stream. Down goes deeper into one thread: the start item, then
/// its neighbours from your own library, a synthesis card after five, and a
/// card when the thread runs dry. Sideways changes thread, on purpose only.
struct StreamView: View {
    @Environment(Store.self) private var store
    @State private var threadIndex = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $threadIndex) {
                ForEach(Array(store.deck.themes.enumerated()), id: \.element.id) { i, theme in
                    ThreadView(theme: theme, number: i + 1, total: store.deck.themes.count)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(store.deck.themes[safe: threadIndex]?.name ?? "Stream")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ThreadView: View {
    @Environment(Store.self) private var store
    let theme: Theme
    let number: Int
    let total: Int
    @State private var items: [Item] = []
    @State private var reading: Item?
    @State private var acted: [String: Decision] = [:]
    @State private var feedback = 0

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    pageView(page)
                        .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .sheet(item: $reading) { ReaderView(item: $0) }
        .sensoryFeedback(.selection, trigger: feedback)
        .onAppear { if items.isEmpty { items = store.thread(theme: theme.name) } }
    }

    private enum Page { case intro, item(Item, Int), synthesis(Synthesis), marker(Int), dry }

    private var pages: [Page] {
        var out: [Page] = [.intro]
        for (i, item) in items.enumerated() {
            out.append(.item(item, i))
            if i == 4, let s = store.synthesis(for: theme.name) { out.append(.synthesis(s)) }
            if i > 0, (i + 1) % 6 == 0 { out.append(.marker(i + 1)) }
        }
        out.append(.dry)
        return out
    }

    @ViewBuilder private func pageView(_ page: Page) -> some View {
        switch page {
        case .intro:
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                Text("Thread \(number) of \(total)").font(.caption).foregroundStyle(.secondary)
                Text(theme.name).font(.largeTitle.weight(.bold)).foregroundStyle(theme.color)
                if !theme.summary.isEmpty { Text(theme.summary).font(.body).foregroundStyle(.secondary) }
                Text("\(items.count) in this thread from your library").font(.callout)
                Spacer()
                Label("Swipe up to go deeper · sideways for another thread", systemImage: "arrow.up")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
        case .item(let item, let depth):
            VStack(spacing: 10) {
                if depth > 0 {
                    Text(depthLabel(depth)).font(.caption2).foregroundStyle(.tertiary)
                }
                CardView(item: item)
                    .onTapGesture { reading = item; store.record(item, .read, mode: "stream", position: depth, thread: theme.name) }
                actions(item, depth: depth)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        case .synthesis(let s):
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                Label("What these add up to", systemImage: "sparkles").font(.headline).foregroundStyle(theme.color)
                Text(s.text).font(.title3)
                Text("From \(s.items.count) links in your library, written by your Claude.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
        case .marker(let n):
            VStack(spacing: 8) {
                Spacer()
                Text("\(store.minutesThisSession) min · \(n) deep · \(acted.count) decided")
                    .font(.title3.weight(.semibold))
                Text("Still in \(theme.name).").foregroundStyle(.secondary)
                Spacer()
            }
        case .dry:
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "drop").font(.system(size: 40)).foregroundStyle(theme.color)
                Text("That's everything you saved on this").font(.title3.weight(.semibold))
                Text("\(acted.count) decided in this thread. Swipe sideways for the next thread, or stop here.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
        }
    }

    private func depthLabel(_ depth: Int) -> String {
        depth == 1 ? "Near the first one" : "\(depth) steps in"
    }

    private func actions(_ item: Item, depth: Int) -> some View {
        HStack(spacing: 10) {
            ForEach([Decision.letGo, .send, .keep], id: \.self) { d in
                Button {
                    acted[item.id] = d
                    feedback += 1
                    store.record(item, d, mode: "stream", position: depth, thread: theme.name)
                } label: {
                    Label(d.label, systemImage: d.symbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(acted[item.id] == d ? d.color : .secondary)
            }
        }
        .font(.callout)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
