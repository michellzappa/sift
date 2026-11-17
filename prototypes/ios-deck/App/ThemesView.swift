import SwiftUI

/// Themes (owner, 2026-11-17): the interest graph as a tab. The mode tabs
/// are streams that end; here you go by interest. Each theme shows what is
/// waiting in each mode. A theme page puts the three modes on one page as
/// shelves (Watch posters sideways, the top reads, a few headlines), with
/// Today's picks that fit the theme on top and the linked themes at the
/// foot, so you walk the graph one theme at a time. Feeds, the review deck
/// and Log sit in the toolbar menu.
struct ThemesView: View {
    @Environment(Store.self) private var store
    @State private var showLog = false
    @State private var showDeck = false
    @State private var path = NavigationPath()

    /// Themes with the newest save first.
    private var themes: [Theme] {
        var newest: [String: String] = [:]
        for item in store.deck.items { if let s = item.saved, s > newest[item.theme] ?? "" { newest[item.theme] = s } }
        return store.deck.themes.sorted { (newest[$0.name] ?? "") > (newest[$1.name] ?? "") }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !store.deck.themes.isEmpty {
                    ThemeGraph { path.append($0) }
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                ForEach(themes) { theme in
                    NavigationLink(value: theme) { ThemeRow(theme: theme) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Themes")
            .navigationDestination(for: Theme.self) { ThemePage(theme: $0) }
            .overlay {
                if store.deck.themes.isEmpty {
                    ContentUnavailableView("No themes yet", systemImage: "circle.hexagongrid",
                                           description: Text("Themes come from your Mac. Import the library: the menu at the top right, then Settings."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            LinkList(title: "All Unseen", items: store.deck.items, unseenOnly: true)
                        } label: { Label("All Unseen", systemImage: "circle.inset.filled") }
                        Button { showDeck = true } label: { Label("Review Deck", systemImage: "rectangle.stack") }
                        NavigationLink { CreatorGraphView() } label: { Label("Your Graph", systemImage: "person.2") }
                        NavigationLink { FeedsView() } label: { Label("Feeds", systemImage: "dot.radiowaves.up.forward") }
                        Button { showLog = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showLog) { LogView() }
            .fullScreenCover(isPresented: $showDeck) {
                LibraryView().overlay(alignment: .topLeading) {
                    Button { showDeck = false } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                        .padding()
                }
            }
            .refreshable { store.sync() }
        }
    }
}

/// Unseen saved items of a theme per mode, for the row and the page.
extension Store {
    func unseen(theme: String) -> [ReadingMode: Int] {
        var counts: [ReadingMode: Int] = [:]
        var urls = Set<String>()
        for item in deck.items where item.theme == theme && !isSeen(item.url) && urls.insert(item.url).inserted {
            counts[item.readingMode, default: 0] += 1
        }
        return counts
    }

    /// Today's picks that fit a theme (the Mac's reason line "Fits <theme>").
    func todayPicks(theme: String) -> [TodayPick] {
        (today?.picks ?? []).filter { $0.reason == "Fits \(theme)" && !isSeen($0.url) }
    }

    /// Themes linked to this one: links of this theme that also feed
    /// another, and links of other themes that feed this one. Most shared first.
    func linkedThemes(_ theme: String) -> [(theme: Theme, shared: Int)] {
        var shared: [String: Int] = [:]
        for item in deck.items {
            if item.theme == theme {
                for other in item.also where other != theme { shared[other, default: 0] += 1 }
            } else if item.also.contains(theme) {
                shared[item.theme, default: 0] += 1
            }
        }
        let byName = Dictionary(deck.themes.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return shared.compactMap { name, n in byName[name].map { ($0, n) } }.sorted { $0.shared > $1.shared }
    }
}

private struct ThemeRow: View {
    @Environment(Store.self) private var store
    let theme: Theme

    var body: some View {
        let counts = store.unseen(theme: theme.name)
        let today = store.todayPicks(theme: theme.name).count
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(theme.color).frame(width: 10, height: 10).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.name).font(.headline)
                if !theme.summary.isEmpty {
                    Text(theme.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    if today > 0 {
                        Label("\(today) today", systemImage: "sun.max").foregroundStyle(.orange)
                    }
                    ForEach(ReadingMode.allCases) { mode in
                        if let n = counts[mode], n > 0 { Label("\(n)", systemImage: mode.symbol) }
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One theme: Today's picks that fit it, then a shelf per mode, then the
/// linked themes.
struct ThemePage: View {
    @Environment(Store.self) private var store
    let theme: Theme
    @State private var reading: Item?

    /// The theme's saved items in one mode, unseen first, then newest.
    private func items(_ mode: ReadingMode) -> [Item] {
        var urls = Set<String>()
        let all = store.deck.items.filter { $0.theme == theme.name && $0.readingMode == mode && urls.insert($0.url).inserted }
            .sorted { ($0.saved ?? "") > ($1.saved ?? "") }
        return all.filter { !store.isSeen($0.url) } + all.filter { store.isSeen($0.url) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !theme.summary.isEmpty {
                    Text(theme.summary).font(.callout).foregroundStyle(.secondary)
                }
                let picks = store.todayPicks(theme: theme.name)
                if !picks.isEmpty {
                    shelf("In Today", symbol: "sun.max", all: nil) {
                        ForEach(picks) { pick in
                            Button { open(pick.item) } label: { pickRow(pick) }.buttonStyle(.plain)
                        }
                    }
                }
                watchShelf
                listShelf(.read, show: 3)
                listShelf(.scan, show: 5)
                people
                linked
            }
            .padding(16)
        }
        .navigationTitle(theme.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $reading) { ReaderView(item: $0) }
    }

    @ViewBuilder private var watchShelf: some View {
        let videos = items(.watch)
        if !videos.isEmpty {
            shelf("Watch", symbol: ReadingMode.watch.symbol, all: videos) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(videos.prefix(20)) { item in
                            let seen = store.isSeen(item.url)
                            Button { open(item) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ItemImage(item: item, height: 124)
                                        .frame(width: 220, height: 124)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .saturation(seen ? 0 : 1)
                                        .overlay(alignment: .bottomTrailing) {
                                            if let length = item.length {
                                                Text(length).font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(.black.opacity(0.65), in: Capsule())
                                                    .foregroundStyle(.white).padding(6)
                                            }
                                        }
                                    Text(item.title).font(.subheadline.weight(seen ? .regular : .semibold))
                                        .foregroundStyle(seen ? .secondary : .primary)
                                        .lineLimit(2).frame(width: 220, alignment: .leading)
                                    Text(item.site).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -16)
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        }
    }

    @ViewBuilder private func listShelf(_ mode: ReadingMode, show: Int) -> some View {
        let list = items(mode)
        if !list.isEmpty {
            shelf(mode.title, symbol: mode.symbol, all: list) {
                ForEach(list.prefix(show)) { item in
                    Button { open(item) } label: { LibraryRow(item: item, mode: mode) }.buttonStyle(.plain)
                    if item.id != list.prefix(show).last?.id { Divider() }
                }
            }
        }
    }

    /// Your Graph inside the theme: who you save from about it, with Follow.
    @ViewBuilder private var people: some View {
        let list = store.creators(theme: theme.name)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Who you save from", systemImage: "person.2").font(.headline)
                    Spacer()
                    NavigationLink("Your Graph") { CreatorGraphView() }.font(.subheadline)
                }
                ForEach(list.prefix(6)) { c in
                    HStack(spacing: 10) {
                        NavigationLink { CreatorPage(creator: c) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
                                Text("\(c.themes[theme.name] ?? 0) here · \(c.count) saved in all").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if store.isFollowing(c) {
                            Text("Following").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        } else {
                            Button("Follow") { store.follow(c) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                Text("Following a creator brings its new posts into Today.").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private var linked: some View {
        let links = store.linkedThemes(theme.name)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Linked themes", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(links, id: \.theme.id) { link in
                        NavigationLink(value: link.theme) {
                            HStack(spacing: 6) {
                                Circle().fill(link.theme.color).frame(width: 8, height: 8)
                                Text(link.theme.name).font(.subheadline)
                                Text("\(link.shared)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("The number is the links the two themes share.").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// A shelf heading with "All N" when there is more to see.
    private func shelf<Content: View>(_ title: String, symbol: String, all: [Item]?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                if let all {
                    NavigationLink("All \(all.count)") {
                        LinkList(title: "\(theme.name): \(title)", items: all, unseenOnly: false)
                    }
                    .font(.subheadline)
                }
            }
            content()
        }
    }

    private func pickRow(_ pick: TodayPick) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.title).font(.body.weight(.semibold)).lineLimit(2)
                Text(pick.feedTitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: pick.readingMode.symbol).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func open(_ item: Item) {
        store.setSeen([item], true, mode: "theme")
        store.record(item, .open, mode: "theme", position: 0)
        reading = item
    }
}

/// Chips that wrap onto the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (width: CGFloat, height: CGFloat) {
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, s.height)
        }
        return (widest, y + line)
    }
}

/// The interest graph above the theme list, like the Mac's Overview: a hub
/// per theme (size by links), its saved links as dots spiralling out by
/// recency (newest nearest; solid = text or transcript saved, ring = title
/// only), and a line between themes that share links (thicker = more).
/// For curiosity more than navigation: a tap on a hub opens the theme.
struct ThemeGraph: View {
    @Environment(Store.self) private var store
    var open: (Theme) -> Void
    @State private var layout: [String: CGPoint] = [:]

    private struct Edge: Hashable { var a: String; var b: String }

    private var edges: [Edge: Int] {
        var e: [Edge: Int] = [:]
        for item in store.deck.items {
            for other in item.also where other != item.theme {
                let pair = [item.theme, other].sorted()
                e[Edge(a: pair[0], b: pair[1]), default: 0] += 1
            }
        }
        return e
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(&ctx, size: size) }
                .contentShape(Rectangle())
                .onTapGesture { location in tap(location, size: geo.size) }
        }
        .onAppear(perform: arrange)
        .onChange(of: store.deck.themes.map(\.name)) { _, _ in arrange() }
    }

    private func point(_ name: String, _ size: CGSize) -> CGPoint? {
        guard let n = layout[name] else { return nil }
        return CGPoint(x: 24 + n.x * (size.width - 48), y: 24 + n.y * (size.height - 48))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let themes = store.deck.themes
        let edges = edges
        let maxCount = CGFloat(max(themes.map(\.count).max() ?? 1, 1))
        let maxEdge = CGFloat(max(edges.values.max() ?? 1, 1))
        for (edge, n) in edges {
            guard let a = point(edge.a, size), let b = point(edge.b, size) else { continue }
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            let width: CGFloat = 0.5 + 3 * CGFloat(n) / maxEdge
            ctx.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: width)
        }
        for theme in themes {
            guard let c = point(theme.name, size) else { continue }
            let hub: CGFloat = 5 + 9 * sqrt(CGFloat(theme.count) / maxCount)
            let leaves = Array(store.deck.items.filter { $0.theme == theme.name }
                .sorted { ($0.saved ?? "") > ($1.saved ?? "") }.prefix(60))
            for (i, item) in leaves.enumerated() {
                let angle = Double(i) * 2.39996
                let r: CGFloat = hub + 4 + 3.2 * CGFloat(sqrt(Double(i + 1)))
                let p = CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
                let dot = Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2))
                let full = !item.text.isEmpty || !item.transcript.isEmpty
                let color = theme.color.opacity(store.isSeen(item.url) ? 0.35 : 0.9)
                if full { ctx.fill(dot, with: .color(color)) } else { ctx.stroke(dot, with: .color(color), lineWidth: 0.7) }
            }
            let disc = CGRect(x: c.x - hub, y: c.y - hub, width: hub * 2, height: hub * 2)
            ctx.fill(Path(ellipseIn: disc), with: .color(theme.color))
            let label = ctx.resolve(Text(theme.name).font(.caption2.weight(.semibold)))
            let below: CGFloat = hub + 9 + 3.2 * CGFloat(sqrt(Double(leaves.count)))
            ctx.draw(label, at: CGPoint(x: c.x, y: c.y + below), anchor: .top)
        }
    }

    private func tap(_ location: CGPoint, size: CGSize) {
        let hit = store.deck.themes.min { dist($0, location, size) < dist($1, location, size) }
        if let hit, dist(hit, location, size) < 44 { open(hit) }
    }

    private func dist(_ t: Theme, _ p: CGPoint, _ size: CGSize) -> CGFloat {
        guard let n = layout[t.name] else { return .infinity }
        let c = CGPoint(x: 24 + n.x * (size.width - 48), y: 24 + n.y * (size.height - 48))
        return hypot(c.x - p.x, c.y - p.y)
    }

    /// A small force layout, run once: themes push apart, shared links
    /// pull together. Positions are 0…1 in both directions.
    private func arrange() {
        let names = store.deck.themes.map(\.name)
        guard !names.isEmpty else { return }
        var pos: [String: CGPoint] = [:]
        for (i, n) in names.enumerated() {
            let a = Double(i) / Double(names.count) * 2 * .pi
            pos[n] = CGPoint(x: 0.5 + 0.35 * cos(a), y: 0.5 + 0.35 * sin(a))
        }
        let edges = edges
        let maxEdge = Double(max(edges.values.max() ?? 1, 1))
        for step in 0..<300 {
            var move: [String: CGVector] = [:]
            for a in names {
                for b in names where a < b {
                    let pa = pos[a]!, pb = pos[b]!
                    let dx = pa.x - pb.x, dy = pa.y - pb.y
                    let d2 = max(dx * dx + dy * dy, 0.0004)
                    let f = 0.004 / d2
                    move[a, default: .zero].dx += dx * f; move[a, default: .zero].dy += dy * f
                    move[b, default: .zero].dx -= dx * f; move[b, default: .zero].dy -= dy * f
                }
            }
            for (e, n) in edges {
                guard let pa = pos[e.a], let pb = pos[e.b] else { continue }
                let k = 0.05 * Double(n) / maxEdge
                let dx = pb.x - pa.x, dy = pb.y - pa.y
                move[e.a, default: .zero].dx += dx * k; move[e.a, default: .zero].dy += dy * k
                move[e.b, default: .zero].dx -= dx * k; move[e.b, default: .zero].dy -= dy * k
            }
            let cool = 1 - Double(step) / 300
            for n in names {
                var p = pos[n]!
                let m = move[n] ?? .zero
                p.x += max(-0.03, min(0.03, m.dx + (0.5 - p.x) * 0.01)) * cool
                p.y += max(-0.03, min(0.03, m.dy + (0.5 - p.y) * 0.01)) * cool
                pos[n] = p
            }
        }
        // Fit into 0…1.
        let xs = pos.values.map(\.x), ys = pos.values.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let w = max(maxX - minX, 0.001), h = max(maxY - minY, 0.001)
        layout = pos.mapValues { CGPoint(x: ($0.x - minX) / w, y: ($0.y - minY) / h) }
    }
}
