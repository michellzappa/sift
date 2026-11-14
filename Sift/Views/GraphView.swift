import SwiftUI

/// The overview graph, with two zoom levels.
///
/// Theme level: one node per theme, sized by its links, joined where themes
/// share sources (the same site or the same linked domain). Only theme names
/// show. Click a theme, or double-click it, to zoom in.
///
/// Link level: the chosen theme in the middle, its links around it as small
/// cards with image, title and site. The other themes wait at the edge;
/// click one to move there, or press Esc / the back button to zoom out.
struct GraphView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    @State private var sim = GraphSimulation()
    @State private var focusTheme: String?
    @State private var hover: Int?
    @State private var offset: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var pinchBase: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let theme = focusTheme {
                    LinkLevel(theme: theme, size: geo.size, color: color(for: theme), others: otherThemes(than: theme)) { next in
                        withAnimation(.snappy) { focusTheme = next }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    themeLevel(size: geo.size)
                        .transition(.opacity.combined(with: .scale(scale: 1.08)))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topLeading) {
            if let theme = focusTheme {
                Button { withAnimation(.snappy) { focusTheme = nil } } label: {
                    Label("All themes", systemImage: "chevron.left")
                }
                .keyboardShortcut(.escape, modifiers: [])
                .padding(12)
                .help("Back to all themes (Esc)")
                .accessibilityLabel("Back to all themes from \(theme)")
            }
        }
        .onAppear { rebuild() }
        .onChange(of: dataKey) { rebuild() }
    }

    // MARK: Theme level

    private func themeLevel(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
        return TimelineView(.animation(paused: !sim.isMoving)) { timeline in
            Canvas { ctx, _ in
                _ = timeline.date
                sim.tick()
                drawThemes(&ctx, center: center)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in offset = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height) }
                .onEnded { _ in panBase = offset }
        )
        .simultaneousGesture(MagnifyGesture()
            .onChanged { scale = min(3, max(0.4, pinchBase * $0.magnification)) }
            .onEnded { _ in pinchBase = scale })
        .onTapGesture { p in
            if let i = hit(p, center: center) { withAnimation(.snappy) { focusTheme = sim.nodes[i].key } }
        }
        .onContinuousHover { phase in
            if case .active(let p) = phase { hover = hit(p, center: center) } else { hover = nil }
        }
        .overlay(alignment: .bottomLeading) {
            Text("Click a theme to see its links. Lines join themes that share sources.")
                .font(.caption).foregroundStyle(.secondary).padding(12)
        }
    }

    private func screen(_ p: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale)
    }

    private func drawThemes(_ ctx: inout GraphicsContext, center: CGPoint) {
        let neighbours = hover.map { sim.neighbours(of: $0) } ?? []
        for e in sim.edges {
            let a = screen(sim.nodes[e.a].p, center: center), b = screen(sim.nodes[e.b].p, center: center)
            var path = Path(); path.move(to: a); path.addLine(to: b)
            let lit = hover == e.a || hover == e.b
            let opacity = hover == nil ? min(0.08 + 0.05 * Double(e.weight), 0.4) : (lit ? 0.6 : 0.04)
            ctx.stroke(path, with: .color((lit ? Color.accentColor : Color.primary).opacity(opacity)),
                       style: StrokeStyle(lineWidth: min(1 + CGFloat(e.weight) * 0.8, 6), lineCap: .round))
        }
        for (i, n) in sim.nodes.enumerated() {
            let p = screen(n.p, center: center)
            let r = n.radius * scale
            let dim = hover != nil && hover != i && !neighbours.contains(i)
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(n.color.opacity(dim ? 0.04 : (hover == i ? 0.16 : 0.08))))
            // One dot per link, packed in a sunflower spiral, so size and
            // density read at a glance.
            let dot = max(2.2, 3.2 * scale)
            var dots = Path()
            for k in 0..<n.count {
                let q = GraphSimulation.dotOffset(k, scale: scale)
                dots.addEllipse(in: CGRect(x: p.x + q.x - dot, y: p.y + q.y - dot, width: dot * 2, height: dot * 2))
            }
            ctx.fill(dots, with: .color(n.color.opacity(dim ? 0.2 : 0.85)))
        }
        for (i, n) in sim.nodes.enumerated() {
            let p = screen(n.p, center: center)
            let r = n.radius * scale
            let dim = hover != nil && hover != i && !neighbours.contains(i)
            let title = Text(n.label).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dim ? Color.secondary.opacity(0.5) : Color.primary)
            + Text("  \(n.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            var resolved = ctx.resolve(title)
            resolved.shading = .color(.primary)
            let maxWidth = GraphSimulation.labelWidth
            let size = resolved.measure(in: CGSize(width: maxWidth, height: 60))
            let box = CGRect(x: p.x - size.width / 2, y: p.y + r + 6, width: size.width, height: size.height)
            ctx.fill(Path(roundedRect: box.insetBy(dx: -5, dy: -2), cornerRadius: 5), with: .color(Color(nsColor: .textBackgroundColor).opacity(0.85)))
            ctx.draw(title, in: box)
        }
    }

    private func hit(_ point: CGPoint, center: CGPoint) -> Int? {
        sim.nodes.indices.first { i in
            let p = screen(sim.nodes[i].p, center: center)
            return hypot(p.x - point.x, p.y - point.y) <= sim.nodes[i].radius * scale + 4
        }
    }

    // MARK: Data

    private var dataKey: String {
        "\(model.tabs.count)-\(model.state.assignments.count)-\(model.themes.map(\.name).joined())"
    }

    private var themeNames: [String] {
        model.projects.map(\.name).filter { model.count($0) > 0 }
    }

    private func color(for theme: String) -> Color {
        let names = model.projects.map(\.name)
        let i = names.firstIndex(of: theme) ?? 0
        return GraphSimulation.palette[i % GraphSimulation.palette.count]
    }

    private func otherThemes(than theme: String) -> [(name: String, color: Color)] {
        themeNames.filter { $0 != theme }.map { ($0, color(for: $0)) }
    }

    /// Hosts too general to say two themes are related.
    private static let genericHosts: Set<String> = [
        "x.com", "twitter.com", "youtube.com", "m.youtube.com", "youtu.be", "reddit.com", "old.reddit.com",
        "threads.com", "threads.net", "linkedin.com", "google.com", "t.co", "medium.com", "substack.com",
    ]

    private func rebuild() {
        let names = themeNames
        // The sources of each theme: the tab's site and, for X posts, the
        // domain the post links to.
        var sources: [String: Set<String>] = [:]
        for tab in model.tabs {
            guard let theme = model.assignment(for: tab)?.project, names.contains(theme) else { continue }
            var hosts: [String] = [tab.host]
            if let out = model.previews[tab.url]?.outboundURL, let h = URL(string: out)?.host() {
                hosts.append(h.hasPrefix("www.") ? String(h.dropFirst(4)) : h)
            }
            for h in hosts where !Self.genericHosts.contains(h) { sources[theme, default: []].insert(h) }
        }
        let nodes = names.map { name in
            GraphSimulation.Node(key: name, label: name, color: color(for: name),
                                 radius: GraphSimulation.clusterRadius(model.count(name)), count: model.count(name))
        }
        var edges: [GraphSimulation.Edge] = []
        for i in names.indices {
            for j in names.indices where j > i {
                let shared = (sources[names[i]] ?? []).intersection(sources[names[j]] ?? []).count
                if shared > 0 { edges.append(.init(a: i, b: j, weight: shared)) }
            }
        }
        sim.load(nodes: nodes, edges: edges)
        if let f = focusTheme, !names.contains(f) { focusTheme = nil }
    }
}

// MARK: - Link level

/// One theme zoomed in: its links as small cards in rings around it.
private struct LinkLevel: View {
    @Environment(AppModel.self) private var model
    let theme: String
    let size: CGSize
    let color: Color
    let others: [(name: String, color: Color)]
    let go: (String) -> Void
    @State private var picked: String?

    private static let chip = CGSize(width: 210, height: 58)

    var body: some View {
        let tabs = model.tabs(in: theme)
        let positions = Self.rings(count: tabs.count, size: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        ZStack {
            Canvas { ctx, _ in
                for p in positions {
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: CGPoint(x: center.x + p.x, y: center.y + p.y))
                    ctx.stroke(path, with: .color(color.opacity(0.18)), lineWidth: 1)
                }
            }
            VStack(spacing: 2) {
                Text(theme).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                if let summary = model.projects.first(where: { $0.name == theme })?.summary, !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
                }
                Text("\(tabs.count) links").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(width: 220)
            .padding(14)
            .background(Circle().fill(color.opacity(0.14)).overlay(Circle().strokeBorder(color.opacity(0.6))).frame(width: 250, height: 250))
            .position(center)

            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                if positions.indices.contains(index) {
                    LinkChip(tab: tab, color: color, isPicked: picked == tab.url)
                        .frame(width: Self.chip.width, height: Self.chip.height)
                        .position(x: center.x + positions[index].x, y: center.y + positions[index].y)
                        .onTapGesture(count: 2) { TabActions.openInSafari(tab.url) }
                        .onTapGesture { picked = picked == tab.url ? nil : tab.url }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .trailing) { otherThemesRail }
        .overlay(alignment: .bottom) { pickedCard(tabs) }
    }

    /// Positions on rings around the center, sized so chips do not overlap.
    static func rings(count: Int, size: CGSize) -> [CGPoint] {
        var out: [CGPoint] = []
        var radius: CGFloat = 200
        var ring = 0
        while out.count < count {
            let circumference = 2 * .pi * radius
            let capacity = max(4, Int(circumference / (chip.width * 0.62)))
            let n = min(capacity, count - out.count)
            let start = ring.isMultiple(of: 2) ? 0.0 : .pi / Double(n)
            for k in 0..<n {
                let a = start + 2 * .pi * Double(k) / Double(n) - .pi / 2
                // Ellipse: wider than tall, to fit a window.
                out.append(CGPoint(x: cos(a) * radius * 1.35, y: sin(a) * radius * 0.8))
            }
            radius += 95
            ring += 1
        }
        return out
    }

    private var otherThemesRail: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(others, id: \.name) { other in
                    Button { go(other.name) } label: {
                        HStack(spacing: 6) {
                            Text(other.name).lineLimit(1)
                            Text("\(model.count(other.name))").monospacedDigit().foregroundStyle(.secondary)
                            Circle().fill(other.color).frame(width: 8, height: 8)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: 260)
        .background(.regularMaterial.opacity(0.6))
    }

    @ViewBuilder
    private func pickedCard(_ tabs: [SafariTab]) -> some View {
        if let url = picked, let tab = tabs.first(where: { $0.url == url }) {
            let a = model.assignment(for: tab)
            let p = model.previews[tab.url]
            HStack(alignment: .top, spacing: 12) {
                if let s = p?.imageURL ?? p?.avatarURL, let image = URL(string: s) {
                    AsyncImage(url: image) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.secondary.opacity(0.1) }
                        .frame(width: 120, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(LinkChip.title(tab, p)).font(.headline).lineLimit(3)
                    if let use = a?.use, !use.isEmpty { Text(use).font(.callout).foregroundStyle(.tint) }
                    HStack(spacing: 6) {
                        Text(tab.host)
                        if let action = a?.action { Text("·"); Label(action.label, systemImage: action.symbol) }
                        if let out = p?.outboundURL, let u = URL(string: out) { Text("·"); Text("→ \(u.host() ?? out)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Open in Safari") { TabActions.openInSafari(tab.url) }
                        if let out = p?.outboundURL { Button("Open Linked Page") { TabActions.openInSafari(out) } }
                    }
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button { picked = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(12)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(16)
        }
    }
}

/// A link at link level: thumbnail (page image, author avatar or site icon),
/// title and site.
private struct LinkChip: View {
    @Environment(AppModel.self) private var model
    let tab: SafariTab
    let color: Color
    let isPicked: Bool

    var body: some View {
        let p = model.previews[tab.url]
        HStack(spacing: 8) {
            thumbnail(p)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: p?.site == "x.com" && p?.imageURL == nil ? 21 : 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(tab, p)).font(.caption.weight(.medium)).lineLimit(2)
                HStack(spacing: 4) {
                    if let action = model.assignment(for: tab)?.action { Image(systemName: action.symbol) }
                    Text(p?.site == "x.com" ? (p?.title ?? "x.com") : tab.host).lineLimit(1)
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isPicked ? Color.accentColor : color.opacity(0.35), lineWidth: isPicked ? 2 : 1))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .task(id: tab.url) { await model.preview(for: tab) }
        .help(tab.url)
    }

    @ViewBuilder
    private func thumbnail(_ p: Preview?) -> some View {
        let source = p?.imageURL ?? p?.avatarURL ?? "https://\(tab.host)/favicon.ico"
        AsyncImage(url: URL(string: source)) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    color.opacity(0.15)
                    Text(String(tab.host.prefix(1)).uppercased()).font(.caption.weight(.bold)).foregroundStyle(color)
                }
            }
        }
    }

    static func title(_ tab: SafariTab, _ p: Preview?) -> String {
        if let p, !p.failed, p.site == "x.com", !p.text.isEmpty { return p.text }
        if tab.hasUsefulTitle { return tab.title.replacingOccurrences(of: #" / X$"#, with: "", options: .regularExpression) }
        if let p, !p.failed, !p.title.isEmpty { return p.title }
        return tab.url
    }
}

// MARK: - Simulation

/// Physics for the theme level: repulsion, springs that pull related themes
/// closer the more sources they share, and cooling so it settles.
@MainActor
final class GraphSimulation {
    struct Node {
        let key: String
        let label: String
        let color: Color
        let radius: CGFloat
        let count: Int
        var p: CGPoint = .zero
        var v: CGVector = .zero

        init(key: String, label: String, color: Color, radius: CGFloat, count: Int) {
            self.key = key; self.label = label; self.color = color; self.radius = radius; self.count = count
        }
    }

    struct Edge { let a: Int; let b: Int; let weight: Int }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private var adjacency: [Set<Int>] = []
    private var alpha: CGFloat = 1

    var isMoving: Bool { alpha > 0.01 }

    static let labelWidth: CGFloat = 170
    static let dotSpacing: CGFloat = 8.5

    /// Where link `k` sits inside its cluster (sunflower spiral).
    static func dotOffset(_ k: Int, scale: CGFloat) -> CGPoint {
        let angle = Double(k) * 2.399963
        let r = dotSpacing * scale * sqrt(Double(k) + 0.5)
        return CGPoint(x: cos(angle) * r, y: sin(angle) * r)
    }

    static func clusterRadius(_ count: Int) -> CGFloat {
        dotSpacing * sqrt(CGFloat(count) + 0.5) + 10
    }

    static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo, .mint, .brown, .cyan, .yellow]

    func load(nodes new: [Node], edges newEdges: [Edge]) {
        let old = Dictionary(nodes.map { ($0.key, $0.p) }, uniquingKeysWith: { a, _ in a })
        nodes = new
        for i in nodes.indices {
            if let p = old[nodes[i].key] {
                nodes[i].p = p
            } else {
                let angle = Double(i) * 2.399963
                let r = 60 * sqrt(Double(i) + 1)
                nodes[i].p = CGPoint(x: cos(angle) * r * 1.4, y: sin(angle) * r)
            }
        }
        edges = newEdges
        adjacency = Array(repeating: [], count: nodes.count)
        for e in edges { adjacency[e.a].insert(e.b); adjacency[e.b].insert(e.a) }
        alpha = old.isEmpty ? 1 : 0.4
    }

    func neighbours(of i: Int) -> Set<Int> { adjacency.indices.contains(i) ? adjacency[i] : [] }

    func tick() {
        guard isMoving, !nodes.isEmpty else { return }
        let count = nodes.count
        var force = [CGVector](repeating: .zero, count: count)
        for i in 0..<count {
            for j in (i + 1)..<count {
                let dx = nodes[i].p.x - nodes[j].p.x, dy = nodes[i].p.y - nodes[j].p.y
                let d = max(sqrt(dx * dx + dy * dy), 1)
                // Room for both clusters and their labels underneath.
                let horizontal = abs(dx) > abs(dy)
                let reach = { (n: Node) in horizontal ? max(n.radius, Self.labelWidth / 2) : n.radius + 34 }
                let minGap = reach(nodes[i]) + reach(nodes[j]) + 18
                // Strong push inside the gap, soft charge outside it.
                let f = d < minGap ? (minGap - d) * 0.5 : 2400 / (d * d)
                let fx = f * dx / d, fy = f * dy / d
                force[i].dx += fx; force[i].dy += fy
                force[j].dx -= fx; force[j].dy -= fy
            }
        }
        for e in edges {
            let a = nodes[e.a], b = nodes[e.b]
            let dx = b.p.x - a.p.x, dy = b.p.y - a.p.y
            let d = max(sqrt(dx * dx + dy * dy), 1)
            let rest = a.radius + b.radius + max(30, 140 - CGFloat(e.weight) * 18)
            let f = (d - rest) * 0.012 * min(CGFloat(e.weight), 4)
            let fx = f * dx / d, fy = f * dy / d
            force[e.a].dx += fx; force[e.a].dy += fy
            force[e.b].dx -= fx; force[e.b].dy -= fy
        }
        for i in 0..<count {
            force[i].dx -= nodes[i].p.x * 0.01
            force[i].dy -= nodes[i].p.y * 0.016
            nodes[i].v.dx = (nodes[i].v.dx + force[i].dx * alpha) * 0.7
            nodes[i].v.dy = (nodes[i].v.dy + force[i].dy * alpha) * 0.7
            nodes[i].p.x += nodes[i].v.dx
            nodes[i].p.y += nodes[i].v.dy
        }
        alpha *= 0.985
    }
}
