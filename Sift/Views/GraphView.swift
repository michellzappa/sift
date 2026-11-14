import SwiftUI

/// A force-directed graph in the style of Obsidian's graph view: themes as
/// large nodes, links as small nodes around them, and (optionally) sites as
/// grey nodes that tie links from different themes together.
///
/// Drag the background to pan, scroll or pinch to zoom, drag a node to move
/// it. Click a theme to open it. Click a link to see it; double-click opens
/// it in Safari.
struct GraphView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    @AppStorage("graph.showSites") private var showSites = true
    @State private var sim = GraphSimulation()
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var panBase: CGSize = .zero
    @State private var dragging: Int?
    @State private var hover: Int?
    @State private var picked: Int?
    @State private var lastTap = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height)
            TimelineView(.animation(paused: !sim.isMoving && dragging == nil)) { timeline in
                Canvas { ctx, size in
                    _ = timeline.date
                    sim.tick()
                    draw(&ctx, center: center)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center))
            .simultaneousGesture(MagnifyGesture()
                .onChanged { scale = min(4, max(0.2, pinchBase * $0.magnification)) }
                .onEnded { _ in pinchBase = scale })
            .onContinuousHover { phase in
                if case .active(let p) = phase { hover = hit(p, center: center) } else { hover = nil }
            }
            .background(ScrollZoom { delta in
                scale = min(4, max(0.2, scale * (1 + delta * 0.01)))
                pinchBase = scale
            })
            .overlay(alignment: .bottomLeading) { pickedCard }
            .overlay(alignment: .topTrailing) { controls }
        }
        .onAppear { rebuild() }
        .onChange(of: dataKey) { rebuild() }
        .onChange(of: showSites) { rebuild() }
    }

    // MARK: Data

    /// Changes when the links, their themes or the themes change.
    private var dataKey: String {
        "\(model.tabs.count)-\(model.state.assignments.count)-\(model.themes.map(\.name).joined())"
    }

    private func rebuild() {
        let themes = model.projects.map(\.name) + [Project.personal]
        let palette = GraphSimulation.palette
        var nodes: [GraphSimulation.Node] = []
        var edges: [(Int, Int, CGFloat)] = []
        var themeIndex: [String: Int] = [:]
        for (i, name) in themes.enumerated() {
            let count = model.count(name)
            guard count > 0 else { continue }
            themeIndex[name] = nodes.count
            let color = name == Project.personal ? Color.gray : palette[i % palette.count]
            nodes.append(.init(kind: .theme, key: name, label: name, color: color, radius: 6 + sqrt(CGFloat(count)) * 2.2))
        }
        var siteIndex: [String: Int] = [:]
        if showSites {
            for site in model.sites where site.count >= 4 {
                siteIndex[site.host] = nodes.count
                nodes.append(.init(kind: .site, key: site.host, label: site.host, color: .secondary, radius: 4 + sqrt(CGFloat(site.count))))
            }
        }
        for tab in model.tabs {
            guard let a = model.assignment(for: tab), let t = themeIndex[a.project] else { continue }
            let i = nodes.count
            let preview = model.previews[tab.url]
            let label = tab.hasUsefulTitle ? tab.title : (preview?.failed == false ? (preview?.site == "x.com" ? preview!.text : preview!.title) : tab.host)
            nodes.append(.init(kind: .link, key: tab.url, label: String(label.prefix(80)), color: nodes[t].color, radius: 3))
            edges.append((i, t, 34 + nodes[t].radius))
            if let s = siteIndex[tab.host] { edges.append((i, s, 90)) }
        }
        sim.load(nodes: nodes, edges: edges)
        picked = nil
    }

    // MARK: Drawing

    private func screen(_ p: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale)
    }

    private func draw(_ ctx: inout GraphicsContext, center: CGPoint) {
        let focus = hover ?? picked
        let neighbours = focus.map { sim.neighbours(of: $0) } ?? []

        var lines = Path()
        var lit = Path()
        for e in sim.edges {
            let a = screen(sim.nodes[e.a].p, center: center), b = screen(sim.nodes[e.b].p, center: center)
            if let f = focus, e.a == f || e.b == f { lit.move(to: a); lit.addLine(to: b) } else { lines.move(to: a); lines.addLine(to: b) }
        }
        ctx.stroke(lines, with: .color(.primary.opacity(focus == nil ? 0.10 : 0.04)), lineWidth: 0.6)
        ctx.stroke(lit, with: .color(.accentColor.opacity(0.7)), lineWidth: 1)

        for (i, n) in sim.nodes.enumerated() {
            let p = screen(n.p, center: center)
            let r = n.radius * max(0.6, min(scale, 1.8))
            let dim = focus != nil && i != focus && !neighbours.contains(i)
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(n.color.opacity(dim ? 0.15 : (n.kind == .site ? 0.55 : 0.9))))
            if i == picked { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(.accentColor), lineWidth: 2) }
        }

        // Labels: themes always, sites when zoomed in a little, links when
        // zoomed in or hovered.
        for (i, n) in sim.nodes.enumerated() {
            let show: Bool
            switch n.kind {
            case .theme: show = true
            case .site: show = scale > 0.9 || i == focus
            case .link: show = i == focus || (scale > 2.2 && focus == nil) || (focus != nil && neighbours.contains(i) && scale > 1.4)
            }
            guard show else { continue }
            let p = screen(n.p, center: center)
            let r = n.radius * max(0.6, min(scale, 1.8))
            let dim = focus != nil && i != focus && !neighbours.contains(i)
            let font: Font = n.kind == .theme ? .system(size: 12, weight: .semibold) : .system(size: 10)
            let text = Text(n.label).font(font).foregroundStyle(dim ? Color.secondary.opacity(0.4) : (n.kind == .link ? Color.secondary : Color.primary))
            ctx.draw(text, at: CGPoint(x: p.x, y: p.y + r + 8), anchor: .top)
        }
    }

    // MARK: Interaction

    private func hit(_ point: CGPoint, center: CGPoint) -> Int? {
        var best: (Int, CGFloat)?
        for (i, n) in sim.nodes.enumerated() {
            let p = screen(n.p, center: center)
            let d = hypot(p.x - point.x, p.y - point.y)
            let r = max(6, n.radius * max(0.6, min(scale, 1.8)) + 3)
            if d <= r, best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }

    private func dragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragging == nil, panBase == offset, hypot(v.translation.width, v.translation.height) < 3 {
                    // Not moved yet: decide between node drag and pan on the first move.
                    if let i = hit(v.startLocation, center: center) { dragging = i }
                    return
                }
                if let i = dragging {
                    sim.pin(i, at: CGPoint(x: (v.location.x - center.x) / scale, y: (v.location.y - center.y) / scale))
                } else {
                    offset = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height)
                }
            }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height)
                if let i = dragging {
                    sim.unpin(i)
                    if moved < 3 { tap(i) }
                } else if moved < 3 {
                    picked = hit(v.startLocation, center: center)
                }
                dragging = nil
                panBase = offset
            }
    }

    private func tap(_ i: Int) {
        let n = sim.nodes[i]
        let now = Date()
        let isDouble = now.timeIntervalSince(lastTap) < 0.35 && picked == i
        lastTap = now
        switch n.kind {
        case .theme: selection = .project(n.key)
        case .site: selection = .site(n.key)
        case .link:
            if isDouble { TabActions.openInSafari(n.key) }
            picked = i
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var pickedCard: some View {
        if let i = picked, sim.nodes.indices.contains(i), sim.nodes[i].kind == .link,
           let tab = model.tabs.first(where: { $0.url == sim.nodes[i].key }) {
            let a = model.assignment(for: tab)
            VStack(alignment: .leading, spacing: 6) {
                Text(sim.nodes[i].label).font(.headline).lineLimit(3)
                if let use = a?.use, !use.isEmpty { Text(use).font(.callout).foregroundStyle(.tint) }
                HStack(spacing: 6) {
                    Text(tab.host)
                    if let p = a?.project { Text("·"); Text(p) }
                    if let action = a?.action { Text("·"); Label(action.label, systemImage: action.symbol) }
                }
                .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open in Safari") { TabActions.openInSafari(tab.url) }
                    Button("Close") { picked = nil }
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: 380, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(16)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Toggle("Sites", isOn: $showSites).toggleStyle(.button).help("Show sites as grey nodes that connect links across themes.")
            Button { withAnimation { offset = .zero; panBase = .zero; scale = 1; pinchBase = 1 } } label: { Image(systemName: "scope") }
                .help("Center the graph")
            Button { sim.reheat() } label: { Image(systemName: "wind") }
                .help("Shake the layout")
        }
        .controlSize(.small)
        .padding(10)
    }
}

/// The physics, kept out of SwiftUI state so a frame does not invalidate the
/// view tree. Repulsion between all nodes, springs along edges, a weak pull to
/// the center, and cooling so the layout settles.
@MainActor
final class GraphSimulation {
    enum Kind { case theme, link, site }

    struct Node {
        let kind: Kind
        let key: String
        let label: String
        let color: Color
        let radius: CGFloat
        var p: CGPoint = .zero
        var v: CGVector = .zero
        var pinned = false

        init(kind: Kind, key: String, label: String, color: Color, radius: CGFloat) {
            self.kind = kind; self.key = key; self.label = label; self.color = color; self.radius = radius
        }
    }

    struct Edge { let a: Int; let b: Int; let length: CGFloat }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private var adjacency: [Set<Int>] = []
    private var alpha: CGFloat = 1

    var isMoving: Bool { alpha > 0.02 }

    static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo, .mint, .brown, .cyan, .yellow]

    func load(nodes new: [Node], edges newEdges: [(Int, Int, CGFloat)]) {
        // Keep positions of nodes that stay, so a data change does not throw the layout.
        let old = Dictionary(nodes.map { ($0.key, $0.p) }, uniquingKeysWith: { a, _ in a })
        nodes = new
        let n = max(1, nodes.count)
        for i in nodes.indices {
            if let p = old[nodes[i].key] {
                nodes[i].p = p
            } else {
                // Sunflower start: even spread, no overlap, deterministic.
                let angle = Double(i) * 2.399963
                let r = 12 * sqrt(Double(i) + 1) * (nodes[i].kind == .theme ? 0.6 : 1)
                nodes[i].p = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            }
        }
        edges = newEdges.map { Edge(a: $0.0, b: $0.1, length: $0.2) }
        adjacency = Array(repeating: [], count: n)
        for e in edges { adjacency[e.a].insert(e.b); adjacency[e.b].insert(e.a) }
        alpha = old.isEmpty ? 1 : 0.5
    }

    func neighbours(of i: Int) -> Set<Int> { adjacency.indices.contains(i) ? adjacency[i] : [] }

    func reheat() { alpha = 0.8 }

    func pin(_ i: Int, at p: CGPoint) {
        guard nodes.indices.contains(i) else { return }
        nodes[i].p = p
        nodes[i].v = .zero
        nodes[i].pinned = true
        alpha = max(alpha, 0.3)
    }

    func unpin(_ i: Int) { if nodes.indices.contains(i) { nodes[i].pinned = false } }

    /// One simulation step. Called once per frame while the layout moves.
    func tick() {
        guard isMoving, !nodes.isEmpty else { return }
        let count = nodes.count
        var force = [CGVector](repeating: .zero, count: count)

        // Repulsion: charge scales with node size, cut off far away.
        for i in 0..<count {
            let pi = nodes[i].p
            let qi: CGFloat = nodes[i].kind == .theme ? 900 : nodes[i].kind == .site ? 400 : 60
            for j in (i + 1)..<count {
                let dx = pi.x - nodes[j].p.x, dy = pi.y - nodes[j].p.y
                var d2 = dx * dx + dy * dy
                if d2 > 250_000 { continue }
                d2 = max(d2, 4)
                let qj: CGFloat = nodes[j].kind == .theme ? 900 : nodes[j].kind == .site ? 400 : 60
                let f = sqrt(qi * qj) / d2
                let d = sqrt(d2)
                let fx = f * dx / d, fy = f * dy / d
                force[i].dx += fx; force[i].dy += fy
                force[j].dx -= fx; force[j].dy -= fy
            }
        }
        // Springs.
        for e in edges {
            let a = nodes[e.a].p, b = nodes[e.b].p
            let dx = b.x - a.x, dy = b.y - a.y
            let d = max(sqrt(dx * dx + dy * dy), 0.01)
            let f = (d - e.length) * 0.04
            let fx = f * dx / d, fy = f * dy / d
            force[e.a].dx += fx; force[e.a].dy += fy
            force[e.b].dx -= fx; force[e.b].dy -= fy
        }
        // Gravity and integration.
        for i in 0..<count where !nodes[i].pinned {
            let g: CGFloat = nodes[i].kind == .theme ? 0.012 : 0.004
            force[i].dx -= nodes[i].p.x * g
            force[i].dy -= nodes[i].p.y * g
            var v = nodes[i].v
            v.dx = (v.dx + force[i].dx * alpha) * 0.6
            v.dy = (v.dy + force[i].dy * alpha) * 0.6
            let speed = hypot(v.dx, v.dy)
            if speed > 30 { v.dx *= 30 / speed; v.dy *= 30 / speed }
            nodes[i].v = v
            nodes[i].p.x += v.dx
            nodes[i].p.y += v.dy
        }
        alpha *= 0.99
    }
}

/// Turns scroll-wheel and trackpad scroll into zoom for the graph.
private struct ScrollZoom: NSViewRepresentable {
    let onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ZoomView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { (view as? ZoomView)?.onZoom = onZoom }

    final class ZoomView: NSView {
        var onZoom: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.onZoom?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 4))
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
