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
                    LinkLevel(theme: theme, size: geo.size, color: color(for: theme)) { next in
                        withAnimation(.snappy) { focusTheme = next }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    themeLevel(size: geo.size)
                        .transition(.opacity.combined(with: .scale(scale: 1.08)))
                }
            }
        }
        .background(focusTheme == nil ? AnyShapeStyle(GraphStyle.background) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)))
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
        .overlay {
            if model.tabs.isEmpty {
                ContentUnavailableView("No tabs in this source", systemImage: "safari")
            } else if model.themes.isEmpty {
                ContentUnavailableView {
                    Label("What do you keep coming back to?", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Sift sends your tabs and Reading List to your Claude, which finds the themes in them. You review the themes before anything changes.")
                } actions: {
                    Button("Discover Themes") { Task { await model.discoverThemes() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isDiscovering)
                }
                .background(.background)
            }
        }
        .navigationTitle("Overview")
        .navigationSubtitle("\(model.tabs.count) links · \(model.themes.count) themes")
        .onAppear { rebuild() }
        .onChange(of: dataKey) { rebuild() }
    }

    // MARK: Theme level

    private func themeLevel(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
        return TimelineView(.animation(paused: !sim.isMoving)) { timeline in
            Canvas { ctx, canvasSize in
                _ = timeline.date
                sim.tick()
                drawTree(&ctx, center: center, size: canvasSize)
            }
        }
        .background(GraphStyle.background)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in offset = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height) }
                .onEnded { _ in panBase = offset }
        )
        .simultaneousGesture(MagnifyGesture()
            .onChanged { zoom(to: pinchBase * $0.magnification, around: $0.startLocation, size: size) }
            .onEnded { _ in pinchBase = scale })
        .background(ScrollZoom { delta, location in
            zoom(to: scale * (1 + delta * 0.01), around: location, size: size)
            pinchBase = scale
        })
        .onTapGesture { p in
            guard let i = hit(p, center: center) else { return }
            let n = sim.nodes[i]
            switch n.kind {
            case .theme: withAnimation(.snappy) { focusTheme = n.key }
            case .group, .leaf: if let t = n.theme { withAnimation(.snappy) { focusTheme = t } }
            case .root: break
            }
        }
        .onContinuousHover { phase in
            if case .active(let p) = phase { hover = hit(p, center: center) } else { hover = nil }
        }
        .overlay(alignment: .bottomLeading) {
            Text("Each branch is a theme, each light a link. Click a branch to open it.")
                .font(.caption).foregroundStyle(.white.opacity(0.45)).padding(12)
        }
    }

    /// Zooms so the point under the cursor stays where it is.
    private func zoom(to newScale: CGFloat, around point: CGPoint, size: CGSize) {
        let clamped = min(5, max(0.25, newScale))
        let center = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
        let world = CGPoint(x: (point.x - center.x) / scale, y: (point.y - center.y) / scale)
        let newCenter = CGPoint(x: point.x - world.x * clamped, y: point.y - world.y * clamped)
        offset = CGSize(width: newCenter.x - size.width / 2, height: newCenter.y - size.height / 2)
        panBase = offset
        scale = clamped
    }

    private func screen(_ p: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale)
    }

    /// The branch a node belongs to, for hover highlighting.
    private func branch(of i: Int?) -> String? {
        guard let i, sim.nodes.indices.contains(i) else { return nil }
        return sim.nodes[i].theme
    }

    private func drawTree(_ ctx: inout GraphicsContext, center: CGPoint, size: CGSize) {
        let lit = branch(of: hover)
        let zoomDot = max(0.7, min(scale, 2.2))

        // Lines: thin, warm, colored by their branch.
        for e in sim.edges {
            let a = sim.nodes[e.a], b = sim.nodes[e.b]
            let pa = screen(a.p, center: center), pb = screen(b.p, center: center)
            var path = Path(); path.move(to: pa); path.addLine(to: pb)
            let isBridge = a.kind == .theme && b.kind == .theme
            let dim = lit != nil && b.theme != lit && !(isBridge && a.theme == lit)
            let base = b.color
            let opacity = dim ? 0.08 : (b.kind == .leaf ? 0.38 : 0.6)
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [a.color.opacity(opacity), base.opacity(opacity)]), startPoint: pa, endPoint: pb),
                       lineWidth: (b.kind == .leaf ? 0.7 : b.kind == .group ? 1.1 : 1.6) * zoomDot)
        }

        // Nodes: flat dots in the branch color; links slightly lighter.
        for n in sim.nodes {
            let dim = lit != nil && n.theme != lit
            let p = screen(n.p, center: center)
            let r = n.size * zoomDot
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(n.color.opacity(dim ? 0.2 : (n.kind == .leaf ? 0.75 : 1))))
        }

        // Labels: themes only, in the branch color, under the node.
        for n in sim.nodes where n.kind == .theme {
            let dim = lit != nil && n.theme != lit
            let p = screen(n.p, center: center)
            let text = Text(n.label).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(n.color.opacity(dim ? 0.3 : 1))
            ctx.draw(text, at: CGPoint(x: p.x, y: p.y + n.size * zoomDot + 9), anchor: .top)
        }
    }

    private func hit(_ point: CGPoint, center: CGPoint) -> Int? {
        var best: (Int, CGFloat)?
        let zoomDot = max(0.7, min(scale, 2.2))
        for (i, n) in sim.nodes.enumerated() {
            let p = screen(n.p, center: center)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d <= max(8, n.size * zoomDot + 6), best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
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
        return GraphStyle.branchColors[i % GraphStyle.branchColors.count]
    }

    /// Hosts too general to say two themes are related.
    private static let genericHosts: Set<String> = [
        "x.com", "twitter.com", "youtube.com", "m.youtube.com", "youtu.be", "reddit.com", "old.reddit.com",
        "threads.com", "threads.net", "linkedin.com", "google.com", "t.co", "medium.com", "substack.com",
    ]

    /// Builds the graph: themes joined to each other where they share
    /// sources, a branch per theme, a twig per site
    /// that holds three or more of the theme's links, and a leaf per link.
    private func rebuild() {
        var nodes: [GraphSimulation.Node] = []
        var edges: [GraphSimulation.Edge] = []
        for name in themeNames {
            let tabs = model.tabs(in: name)
            let tint = color(for: name)
            let t = nodes.count
            nodes.append(.init(kind: .theme, key: name, label: name, theme: name, color: tint,
                               size: 4.5 + sqrt(CGFloat(tabs.count)) * 0.9, count: tabs.count))
            let bySite = Dictionary(grouping: tabs, by: \.host)
            for (site, group) in bySite.sorted(by: { $0.value.count > $1.value.count }) {
                var parent = t
                if group.count >= 3 {
                    parent = nodes.count
                    nodes.append(.init(kind: .group, key: "\(name)|\(site)", label: site, theme: name, color: tint,
                                       size: 2.8 + sqrt(CGFloat(group.count)) * 0.5, count: group.count))
                    edges.append(.init(a: t, b: parent, length: 34 + sqrt(CGFloat(group.count)) * 4))
                }
                for tab in group {
                    let leaf = nodes.count
                    nodes.append(.init(kind: .leaf, key: tab.url, label: "", theme: name, color: tint, size: 2.1, count: 1))
                    edges.append(.init(a: parent, b: leaf, length: parent == t ? 26 : 16))
                }
            }
        }
        // Theme to theme: the more sources two themes share (the same site,
        // or posts that link to the same domain), the shorter the line.
        var sources: [String: Set<String>] = [:]
        var themeNode: [String: Int] = [:]
        for (i, n) in nodes.enumerated() where n.kind == .theme { themeNode[n.key] = i }
        for tab in model.tabs {
            guard let theme = model.assignment(for: tab)?.project, themeNode[theme] != nil else { continue }
            var hosts = [tab.host]
            if let out = model.previews[tab.url]?.outboundURL, let h = URL(string: out)?.host() {
                hosts.append(h.hasPrefix("www.") ? String(h.dropFirst(4)) : h)
            }
            for h in hosts where !Self.genericHosts.contains(h) { sources[theme, default: []].insert(h) }
        }
        let names = Array(themeNode.keys).sorted()
        for (x, a) in names.enumerated() {
            for b in names[(x + 1)...] {
                let shared = (sources[a] ?? []).intersection(sources[b] ?? []).count
                guard shared > 0, let ia = themeNode[a], let ib = themeNode[b] else { continue }
                edges.append(.init(a: ia, b: ib, length: max(120, 300 - CGFloat(shared) * 40)))
            }
        }
        sim.load(nodes: nodes, edges: edges)
        if let f = focusTheme, !themeNames.contains(f) { focusTheme = nil }
    }
}

/// Colors and background for the graph. Dark on purpose, in both light and
/// dark mode: the lights read better on night.
enum GraphStyle {
    static let background = LinearGradient(
        colors: [Color(red: 0.12, green: 0.10, blue: 0.16), Color(red: 0.07, green: 0.09, blue: 0.14)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let root = Color(red: 1.0, green: 0.62, blue: 0.22)
    /// Warm to cool, all bright enough to glow on dark.
    static let branchColors: [Color] = [
        Color(red: 1.00, green: 0.66, blue: 0.30), Color(red: 1.00, green: 0.82, blue: 0.40),
        Color(red: 0.98, green: 0.52, blue: 0.42), Color(red: 0.56, green: 0.86, blue: 0.98),
        Color(red: 0.70, green: 0.62, blue: 1.00), Color(red: 0.55, green: 0.95, blue: 0.75),
        Color(red: 1.00, green: 0.60, blue: 0.75), Color(red: 0.95, green: 0.95, blue: 0.70),
        Color(red: 0.62, green: 0.75, blue: 1.00), Color(red: 1.00, green: 0.74, blue: 0.55),
    ]
}

// MARK: - Link level

/// One theme zoomed in: its links as small cards in rings around it.
private struct LinkLevel: View {
    @Environment(AppModel.self) private var model
    let theme: String
    let size: CGSize
    let color: Color
    let go: (String) -> Void
    @State private var picked: String?
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero

    private static let chip = CGSize(width: 210, height: 58)

    var body: some View {
        let tabs = model.tabs(in: theme)
        let browserWidth = min(max(size.width * 0.46, 420), size.width - 320)
        HStack(spacing: 0) {
            ring(tabs, size: picked == nil ? size : CGSize(width: size.width - browserWidth, height: size.height))
            if let url = picked, let tab = tabs.first(where: { $0.url == url }) {
                Divider()
                WebPane(tab: tab) { withAnimation(.snappy) { picked = nil } }
                    .frame(width: browserWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func ring(_ tabs: [SafariTab], size: CGSize) -> some View {
        let positions = Self.rings(count: tabs.count, size: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return ZStack {
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
                        .onTapGesture { withAnimation(.snappy) { picked = picked == tab.url ? nil : tab.url } }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(zoom)
        .offset(pan)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { v in pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height) }
            .onEnded { _ in panBase = pan })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { zoom = min(3, max(0.4, zoomBase * $0.magnification)) }
            .onEnded { _ in zoomBase = zoom })
        .background(ScrollZoom { delta, _ in
            zoom = min(3, max(0.4, zoom * (1 + delta * 0.01)))
            zoomBase = zoom
        })
        .clipped()
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

/// Physics for the tree: every node pushes every other away, edges act as
/// springs with their own rest length, and the root stays in the middle.
/// It cools down and stops, so a settled graph costs nothing.
@MainActor
final class GraphSimulation {
    enum Kind { case root, theme, group, leaf }

    struct Node {
        let kind: Kind
        let key: String
        let label: String
        let theme: String?
        let color: Color
        let size: CGFloat
        let count: Int
        var p: CGPoint = .zero
        var v: CGVector = .zero

        init(kind: Kind, key: String, label: String, theme: String?, color: Color, size: CGFloat, count: Int) {
            self.kind = kind; self.key = key; self.label = label; self.theme = theme
            self.color = color; self.size = size; self.count = count
        }
    }

    struct Edge { let a: Int; let b: Int; let length: CGFloat }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private var alpha: CGFloat = 1

    var isMoving: Bool { alpha > 0.008 }

    /// Kept for the link level, which tints chips by theme.
    static var palette: [Color] { GraphStyle.branchColors }

    func load(nodes new: [Node], edges newEdges: [Edge]) {
        let old = Dictionary(nodes.map { ($0.key, $0.p) }, uniquingKeysWith: { a, _ in a })
        nodes = new
        edges = newEdges
        // New nodes start next to their parent so branches grow outward.
        var parent: [Int: Int] = [:]
        for e in edges { parent[e.b] = e.a }
        for i in nodes.indices {
            if let p = old[nodes[i].key] { nodes[i].p = p; continue }
            let base = parent[i].map { nodes[$0].p } ?? .zero
            let angle = Double(i) * 2.399963
            let r: Double = nodes[i].kind == .theme ? 90 * sqrt(Double(i) + 1) : 14
            nodes[i].p = CGPoint(x: base.x + cos(angle) * r, y: base.y + sin(angle) * r)
        }
        alpha = old.isEmpty ? 1 : 0.5
    }

    func tick() {
        guard isMoving, !nodes.isEmpty else { return }
        let count = nodes.count
        var fx = [CGFloat](repeating: 0, count: count)
        var fy = [CGFloat](repeating: 0, count: count)
        let charge: (Kind) -> CGFloat = { k in
            switch k { case .root: 900; case .theme: 520; case .group: 90; case .leaf: 26 }
        }
        for i in 0..<count {
            let pi = nodes[i].p, qi = charge(nodes[i].kind)
            for j in (i + 1)..<count {
                let dx = pi.x - nodes[j].p.x, dy = pi.y - nodes[j].p.y
                let d2 = max(dx * dx + dy * dy, 9)
                if d2 > 160_000 { continue }
                let f = sqrt(qi * charge(nodes[j].kind)) / d2
                let d = sqrt(d2)
                let ux = dx / d * f, uy = dy / d * f
                fx[i] += ux; fy[i] += uy
                fx[j] -= ux; fy[j] -= uy
            }
        }
        for e in edges {
            let a = nodes[e.a].p, b = nodes[e.b].p
            let dx = b.x - a.x, dy = b.y - a.y
            let d = max(sqrt(dx * dx + dy * dy), 0.1)
            let f = (d - e.length) * 0.08
            let ux = f * dx / d, uy = f * dy / d
            fx[e.a] += ux * 0.3; fy[e.a] += uy * 0.3
            fx[e.b] -= ux; fy[e.b] -= uy
        }
        for i in 0..<count {
            let pull: CGFloat = nodes[i].kind == .theme ? 0.012 : 0.002
            fx[i] -= nodes[i].p.x * pull
            fy[i] -= nodes[i].p.y * pull
            var v = nodes[i].v
            v.dx = (v.dx + fx[i] * alpha) * 0.62
            v.dy = (v.dy + fy[i] * alpha) * 0.62
            let speed = hypot(v.dx, v.dy)
            if speed > 24 { v.dx *= 24 / speed; v.dy *= 24 / speed }
            nodes[i].v = v
            nodes[i].p.x += v.dx
            nodes[i].p.y += v.dy
        }
        alpha *= 0.988
    }
}

/// Turns two-finger trackpad scroll and the mouse wheel into zoom.
/// Reports the delta and the cursor position in the view's coordinates.
struct ScrollZoom: NSViewRepresentable {
    let onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ZoomView {
        let view = ZoomView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ view: ZoomView, context: Context) { view.onZoom = onZoom }

    final class ZoomView: NSView {
        var onZoom: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 6)
                self.onZoom?(delta, point)
                return nil
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
