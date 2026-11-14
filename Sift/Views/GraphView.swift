import SwiftUI

/// The overview: one canvas with two zoom levels.
///
/// Zoomed out, each theme is a node with its links around it as dots, and
/// themes are joined where they share sources (the same site, or posts that
/// link to the same domain). Only theme names show.
///
/// Click a theme and the camera glides onto it: its links unfold around it
/// as small cards with image, title and site, and the rest of the graph
/// fades back. Click a card to read the page in the browser on the right.
/// Esc, or a click on empty space, zooms back out.
struct GraphView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    @State private var sim = GraphSimulation()
    @State private var cam = GraphCamera()
    @State private var focusTheme: String?
    @State private var picked: String?
    @State private var hover: Int?
    @State private var redraw = 0
    @State private var panBase: CGSize?
    @State private var pinchBase: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    private static let chip = CGSize(width: 196, height: 54)

    var body: some View {
        GeometryReader { geo in
            let browserWidth = min(max(geo.size.width * 0.44, 420), geo.size.width - 360)
            let graphSize = picked == nil ? geo.size : CGSize(width: geo.size.width - browserWidth, height: geo.size.height)
            HStack(spacing: 0) {
                canvas(size: graphSize)
                    .frame(width: graphSize.width, height: graphSize.height)
                    .clipped()
                if let url = picked, let tab = model.tabs.first(where: { $0.url == url }) {
                    Divider()
                    WebPane(tab: tab) { withAnimation(.snappy) { picked = nil } }
                        .frame(width: browserWidth)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if focusTheme != nil {
                Button { unfocus() } label: { Label("All themes", systemImage: "chevron.left") }
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding(12)
                    .help("Zoom back out (Esc)")
            }
        }
        .overlay {
            if model.tabs.isEmpty {
                ContentUnavailableView("No tabs in this source", systemImage: "safari")
            }
        }
        .navigationTitle(focusTheme ?? "Overview")
        .navigationSubtitle(focusTheme.map { "\(links(in: $0).count) links" } ?? "\(model.tabs.count) links · \(model.themes.count) themes")
        .onAppear { rebuild() }
        .onChange(of: dataKey) { rebuild() }
    }

    // MARK: Canvas

    private func canvas(size: CGSize) -> some View {
        TimelineView(.animation(paused: !(sim.isMoving || cam.isAnimating))) { timeline in
            let _ = redraw
            ZStack(alignment: .topLeading) {
                Canvas { ctx, canvasSize in
                    _ = timeline.date
                    sim.tick()
                    cam.step()
                    drawGraph(&ctx, size: canvasSize)
                }
                if let theme = focusTheme, let i = nodeIndex(theme) {
                    chips(theme: theme, node: i, size: size)
                }
            }
        }
        .background(GraphStyle.background(scheme))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    let base = panBase ?? cam.offset
                    panBase = base
                    cam.stop()
                    cam.offset = CGSize(width: base.width + v.translation.width, height: base.height + v.translation.height)
                    redraw += 1
                }
                .onEnded { _ in panBase = nil }
        )
        .simultaneousGesture(MagnifyGesture()
            .onChanged { zoom(to: pinchBase * $0.magnification, around: $0.startLocation, size: size) }
            .onEnded { _ in pinchBase = cam.scale })
        // While a theme's cards are open, scrolling scrolls the cards.
        .background(ScrollZoom(isEnabled: focusTheme == nil) { delta, location in
            zoom(to: cam.scale * (1 + delta * 0.01), around: location, size: size)
            pinchBase = cam.scale
        })
        .onTapGesture { p in
            if let i = hit(p, size: size), let theme = sim.nodes[i].theme {
                if theme != focusTheme { focus(theme, size: size) }
            } else if focusTheme != nil {
                unfocus()
            }
        }
        .onContinuousHover { phase in
            if case .active(let p) = phase { hover = hit(p, size: size) } else { hover = nil }
        }
        .overlay(alignment: .bottomLeading) {
            if focusTheme == nil {
                Text("Click a theme to zoom in. Pinch or scroll to zoom, drag to move.")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
    }

    private func zoom(to newScale: CGFloat, around point: CGPoint, size: CGSize) {
        let clamped = min(6, max(0.25, newScale))
        let center = cam.center(in: size)
        let world = CGPoint(x: (point.x - center.x) / cam.scale, y: (point.y - center.y) / cam.scale)
        cam.stop()
        cam.scale = clamped
        cam.offset = CGSize(width: point.x - world.x * clamped - size.width / 2, height: point.y - world.y * clamped - size.height / 2)
        redraw += 1
    }

    /// Glides the camera onto a theme and unfolds its links.
    private func focus(_ theme: String, size: CGSize) {
        guard let i = nodeIndex(theme) else { return }
        let target: CGFloat = 1.8
        let p = sim.nodes[i].p
        cam.animate(to: CGSize(width: -p.x * target, height: -p.y * target), scale: target)
        withAnimation(.easeOut(duration: 0.3)) { focusTheme = theme }
        redraw += 1
    }

    private func unfocus() {
        withAnimation(.snappy) { picked = nil }
        withAnimation(.easeOut(duration: 0.25)) { focusTheme = nil }
        cam.animate(to: .zero, scale: 1)
        redraw += 1
    }

    private func nodeIndex(_ theme: String) -> Int? {
        sim.nodes.firstIndex { $0.kind == .theme && $0.key == theme }
    }

    private func screen(_ p: CGPoint, size: CGSize) -> CGPoint {
        let c = cam.center(in: size)
        return CGPoint(x: c.x + p.x * cam.scale, y: c.y + p.y * cam.scale)
    }

    // MARK: Drawing

    private func drawGraph(_ ctx: inout GraphicsContext, size: CGSize) {
        let lit = focusTheme ?? hover.flatMap { sim.nodes.indices.contains($0) ? sim.nodes[$0].theme : nil }
        let dotScale = max(0.7, min(cam.scale, 2.2))
        // Focused: the theme's own links are drawn as cards, not dots.
        let hidden: (GraphSimulation.Node) -> Bool = { n in
            focusTheme != nil && n.theme == focusTheme && n.kind != .theme
        }

        for e in sim.edges {
            let a = sim.nodes[e.a], b = sim.nodes[e.b]
            if hidden(b) { continue }
            let pa = screen(a.p, size: size), pb = screen(b.p, size: size)
            var path = Path(); path.move(to: pa); path.addLine(to: pb)
            let bridge = a.kind == .theme && b.kind == .theme
            let dim = lit != nil && b.theme != lit && !(bridge && a.theme == lit)
            let opacity = bridge ? (dim ? 0.04 : (lit != nil ? 0.5 : 0.16)) : (dim ? 0.07 : (b.kind == .leaf ? 0.4 : 0.6))
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [a.color.opacity(opacity), b.color.opacity(opacity)]), startPoint: pa, endPoint: pb),
                       lineWidth: (b.kind == .leaf ? 0.7 : b.kind == .group ? 1.1 : 1.2) * dotScale)
        }
        for n in sim.nodes where !hidden(n) {
            let dim = lit != nil && n.theme != lit
            let p = screen(n.p, size: size)
            let r = n.size * dotScale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(n.color.opacity(dim ? 0.18 : (n.kind == .leaf ? 0.75 : 1))))
        }
        for (i, n) in sim.nodes.enumerated() where n.kind == .theme {
            let dim = lit != nil && n.theme != lit
            let p = screen(n.p, size: size)
            let focused = n.key == focusTheme
            let below = focused ? n.size * dotScale : sim.clusterRadius(i) * cam.scale
            let text = Text(n.label).font(.system(size: focused ? 15 : 11.5, weight: .semibold)).foregroundStyle(n.color.opacity(dim ? 0.3 : 1))
            ctx.draw(text, at: CGPoint(x: p.x, y: p.y + below + 6), anchor: .top)
        }
    }

    // MARK: Cards around the focused theme

    /// Every link of the focused theme as a card, in a grid that fits the
    /// view and scrolls when the theme is large, so no card hides another.
    private func chips(theme: String, node: Int, size: CGSize) -> some View {
        let tabs = links(in: theme)
        let color = sim.nodes[node].color
        let summary = model.projects.first(where: { $0.name == theme })?.summary ?? ""
        let fade = min(1.0, max(0.0, Double(cam.scale - 1.1) / 0.6))
        let columns = [TabCard.column]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme).font(.title2.weight(.semibold)).foregroundStyle(color)
                    if !summary.isEmpty { Text(summary).font(.callout).foregroundStyle(.secondary) }
                    Text("\(tabs.count) links").font(.caption).foregroundStyle(.tertiary)
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(tabs) { tab in chipCell(tab, color: color) }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 56)
            .padding(.bottom, 28)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .background(.ultraThinMaterial.opacity(0.85))
        .opacity(fade)
    }

    /// The same card the lists use: image, full title, summary, use, action.
    private func chipCell(_ tab: SafariTab, color: Color) -> some View {
        TabCard(tab: tab, isSelected: picked == tab.url)
            .onTapGesture(count: 2) { TabActions.openInSafari(tab.url) }
            .onTapGesture { withAnimation(.snappy) { picked = picked == tab.url ? nil : tab.url } }
    }

    private func hit(_ point: CGPoint, size: CGSize) -> Int? {
        var best: (Int, CGFloat)?
        let dotScale = max(0.7, min(cam.scale, 2.2))
        for (i, n) in sim.nodes.enumerated() {
            if focusTheme != nil && n.theme == focusTheme && n.kind != .theme { continue }
            let p = screen(n.p, size: size)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d <= max(8, n.size * dotScale + 6), best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }

    // MARK: Data

    private var dataKey: String {
        "\(model.tabs.count)-\(model.state.assignments.count)-\(model.themes.map(\.name).joined())"
    }

    /// Links in no theme yet form their own grey cluster, so the graph is
    /// never empty: you always see your data, sorted or not.
    static let unsortedKey = "Not in a Theme Yet"

    private var themeNames: [String] {
        var names = model.projects.map(\.name).filter { model.count($0) > 0 }
        if model.unsortedCount > 0 { names.append(Self.unsortedKey) }
        return names
    }

    /// The links behind a cluster; the unsorted cluster holds unsorted links.
    private func links(in name: String) -> [SafariTab] {
        name == Self.unsortedKey ? model.tabs(in: nil) : model.tabs(in: name)
    }

    private func color(for theme: String) -> Color {
        if theme == Self.unsortedKey { return .gray }
        let names = model.projects.map(\.name)
        let i = names.firstIndex(of: theme) ?? 0
        return GraphStyle.color(index: i, of: names.count)
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
            // Links sorted by site, so each site's links sit together.
            let tabs = links(in: name).sorted { ($0.host, $0.url) < ($1.host, $1.url) }
            let tint = color(for: name)
            let t = nodes.count
            let size = 5 + sqrt(CGFloat(tabs.count)) * 0.8
            nodes.append(.init(kind: .theme, key: name, label: name, theme: name, color: tint, size: size, count: tabs.count))
            // A sunflower of links around the theme, compact and fixed.
            var local: [String: CGPoint] = [:]
            for (k, tab) in tabs.enumerated() {
                let angle = Double(k) * 2.399963
                let r = Double(size) + 7 + 6.2 * sqrt(Double(k) + 1)
                local[tab.url] = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            }
            let bySite = Dictionary(grouping: tabs, by: \.host)
            for (site, group) in bySite.sorted(by: { $0.key < $1.key }) {
                var parent = t
                if group.count >= 3 {
                    // The twig sits at the middle of its links.
                    let pts = group.compactMap { local[$0.url] }
                    let mid = CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count) * 0.6,
                                      y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count) * 0.6)
                    parent = nodes.count
                    var twig = GraphSimulation.Node(kind: .group, key: "\(name)|\(site)", label: site, theme: name, color: tint,
                                                    size: 2.4 + sqrt(CGFloat(group.count)) * 0.4, count: group.count)
                    twig.anchor = t; twig.local = mid
                    nodes.append(twig)
                    edges.append(.init(a: t, b: parent, length: 0))
                }
                for tab in group {
                    var leaf = GraphSimulation.Node(kind: .leaf, key: tab.url, label: "", theme: name, color: tint, size: 1.9, count: 1)
                    leaf.anchor = t; leaf.local = local[tab.url] ?? .zero
                    let i = nodes.count
                    nodes.append(leaf)
                    edges.append(.init(a: parent, b: i, length: 0))
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
                edges.append(.init(a: ia, b: ib, length: max(30, 150 - CGFloat(shared) * 30), weight: shared))
            }
        }
        sim.load(nodes: nodes, edges: edges)
        if let f = focusTheme, !themeNames.contains(f) { focusTheme = nil }
        // The layout is settled already; draw it now.
        redraw += 1
    }
}

/// Colors and background for the graph. Light in light mode, dark in dark
/// mode. Each branch color has a deeper shade for light backgrounds and a
/// brighter one for dark.
enum GraphStyle {
    static func background(_ scheme: ColorScheme) -> AnyShapeStyle {
        scheme == .dark
            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.12, green: 0.11, blue: 0.16), Color(red: 0.08, green: 0.09, blue: 0.13)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Color(nsColor: .textBackgroundColor))
    }

    /// Theme `index` of `count` themes: hues spread evenly around the wheel,
    /// as far apart as the number of themes allows, all with the same
    /// lightness and chroma (OKLCH) so no theme looks louder than another.
    /// Themes next to each other get hues from opposite sides of the wheel
    /// (a golden-ratio stride). Deeper in light mode, lighter in dark mode.
    static func color(index: Int, of count: Int) -> Color {
        let n = max(count, 1)
        var stride = max(1, Int((Double(n) * 0.382).rounded()))
        while gcd(stride, n) != 1 { stride += 1 }
        let slot = (index * stride) % n
        let hue = (28 + Double(slot) * 360 / Double(n)).truncatingRemainder(dividingBy: 360)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return oklch(dark ? 0.78 : 0.64, dark ? 0.115 : 0.125, hue)
        })
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    /// OKLCH to sRGB, clamped to the sRGB gamut.
    private static func oklch(_ l: Double, _ c: Double, _ hDegrees: Double) -> NSColor {
        let h = hDegrees * .pi / 180
        let a = c * cos(h), b = c * sin(h)
        let l1 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m1 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s1 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        let r = 4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1
        let g = -1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1
        let bl = -0.0041960863 * l1 - 0.7034186147 * m1 + 1.7076147010 * s1
        func encode(_ x: Double) -> CGFloat {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return CGFloat(min(1, max(0, v)))
        }
        return NSColor(srgbRed: encode(r), green: encode(g), blue: encode(bl), alpha: 1)
    }
}

/// A link card around a focused theme: thumbnail (page image, author avatar or site icon),
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


/// Where the canvas looks and how close. Kept out of SwiftUI state so it
/// can glide every frame without rebuilding the view tree.
@MainActor
final class GraphCamera {
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    private var target: (offset: CGSize, scale: CGFloat)?

    var isAnimating: Bool { target != nil }

    func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
    }

    func animate(to offset: CGSize, scale: CGFloat) { target = (offset, scale) }

    func stop() { target = nil }

    /// Eases a little closer to the target each frame.
    func step() {
        guard let t = target else { return }
        let k: CGFloat = 0.16
        offset.width += (t.offset.width - offset.width) * k
        offset.height += (t.offset.height - offset.height) * k
        scale += (t.scale - scale) * k
        if abs(t.scale - scale) < 0.002, abs(t.offset.width - offset.width) < 0.5, abs(t.offset.height - offset.height) < 0.5 {
            offset = t.offset
            scale = t.scale
            target = nil
        }
    }
}

/// Physics for the themes only. Each theme carries a fixed cluster of its
/// links (`anchor` and `local`), so links never push each other around.
/// Themes keep room for their cluster and label, connected themes pull
/// together by how many sources they share, and a gentle pull to the middle
/// keeps unconnected themes near. It cools down and stops.
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
        /// For links and twigs: the theme node they move with, and where.
        var anchor: Int?
        var local: CGPoint = .zero

        init(kind: Kind, key: String, label: String, theme: String?, color: Color, size: CGFloat, count: Int) {
            self.kind = kind; self.key = key; self.label = label; self.theme = theme
            self.color = color; self.size = size; self.count = count
        }
    }

    struct Edge {
        let a: Int
        let b: Int
        /// Gap between two clusters for theme-to-theme edges; unused otherwise.
        let length: CGFloat
        var weight: Int = 0
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private var themes: [Int] = []
    private var extent: [Int: CGFloat] = [:]
    private var labelHalf: [Int: CGFloat] = [:]
    private var alpha: CGFloat = 1

    var isMoving: Bool { alpha > 0.008 }


    func load(nodes new: [Node], edges newEdges: [Edge]) {
        let old = Dictionary(nodes.filter { $0.kind == .theme }.map { ($0.key, $0.p) }, uniquingKeysWith: { a, _ in a })
        nodes = new
        edges = newEdges
        themes = nodes.indices.filter { nodes[$0].kind == .theme }
        extent = [:]
        for i in nodes.indices { if let t = nodes[i].anchor { extent[t] = max(extent[t] ?? 0, hypot(nodes[i].local.x, nodes[i].local.y)) } }
        labelHalf = [:]
        for t in themes { labelHalf[t] = CGFloat(nodes[t].label.count) * 3.4 + 8 }
        for (k, t) in themes.enumerated() {
            if let p = old[nodes[t].key] { nodes[t].p = p; continue }
            let angle = Double(k) * 2.399963
            let r = 70 * sqrt(Double(k) + 1)
            nodes[t].p = CGPoint(x: cos(angle) * r * 1.3, y: sin(angle) * r)
        }
        place()
        // Settle before the first frame, so the graph loads in place and
        // does not move on screen.
        alpha = old.isEmpty ? 1 : 0.5
        var steps = 0
        while isMoving && steps < 1500 { step(); steps += 1 }
        alpha = 0
    }

    private func radius(_ t: Int) -> CGFloat { (extent[t] ?? 0) + nodes[t].size + 4 }

    /// How far a theme's cluster reaches from its center, in graph units.
    func clusterRadius(_ t: Int) -> CGFloat { nodes.indices.contains(t) ? radius(t) : 0 }

    /// Moves every link and twig with its theme.
    private func place() {
        for i in nodes.indices { if let t = nodes[i].anchor { nodes[i].p = CGPoint(x: nodes[t].p.x + nodes[i].local.x, y: nodes[t].p.y + nodes[i].local.y) } }
    }

    /// Called every frame; does nothing once the layout has settled.
    func tick() { if isMoving { step() } }

    private func step() {
        guard !themes.isEmpty else { alpha = 0; return }
        var f: [Int: CGVector] = [:]
        for t in themes { f[t] = .zero }
        // Collision with room for labels: wider than tall.
        for (x, i) in themes.enumerated() {
            for j in themes[(x + 1)...] {
                let dx = nodes[i].p.x - nodes[j].p.x, dy = nodes[i].p.y - nodes[j].p.y
                let d = max(hypot(dx, dy), 0.5)
                let ux = dx / d, uy = dy / d
                let reachI = max(radius(i), abs(ux) * (labelHalf[i] ?? 0)) + abs(uy) * 18
                let reachJ = max(radius(j), abs(ux) * (labelHalf[j] ?? 0)) + abs(uy) * 18
                let gap = reachI + reachJ + 16
                let push = d < gap ? (gap - d) * 0.35 : 900 / (d * d)
                f[i]!.dx += ux * push; f[i]!.dy += uy * push
                f[j]!.dx -= ux * push; f[j]!.dy -= uy * push
            }
        }
        // Shared sources pull themes together.
        for e in edges where nodes[e.a].kind == .theme && nodes[e.b].kind == .theme {
            let a = nodes[e.a].p, b = nodes[e.b].p
            let dx = b.x - a.x, dy = b.y - a.y
            let d = max(hypot(dx, dy), 0.5)
            let rest = radius(e.a) + radius(e.b) + e.length
            let k = 0.015 * min(CGFloat(e.weight), 4)
            let pull = (d - rest) * k
            f[e.a]!.dx += pull * dx / d; f[e.a]!.dy += pull * dy / d
            f[e.b]!.dx -= pull * dx / d; f[e.b]!.dy -= pull * dy / d
        }
        for t in themes {
            var v = nodes[t].v
            v.dx = (v.dx + (f[t]!.dx - nodes[t].p.x * 0.02) * alpha) * 0.6
            v.dy = (v.dy + (f[t]!.dy - nodes[t].p.y * 0.03) * alpha) * 0.6
            let speed = hypot(v.dx, v.dy)
            if speed > 20 { v.dx *= 20 / speed; v.dy *= 20 / speed }
            nodes[t].v = v
            nodes[t].p.x += v.dx
            nodes[t].p.y += v.dy
        }
        place()
        alpha *= 0.985
    }
}

/// Turns two-finger trackpad scroll and the mouse wheel into zoom.
/// Reports the delta and the cursor position in the view's coordinates.
struct ScrollZoom: NSViewRepresentable {
    var isEnabled = true
    let onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ZoomView {
        let view = ZoomView()
        view.onZoom = onZoom
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: ZoomView, context: Context) {
        view.onZoom = onZoom
        view.isEnabled = isEnabled
    }

    final class ZoomView: NSView {
        var onZoom: ((CGFloat, CGPoint) -> Void)?
        var isEnabled = true
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.isEnabled, let window = self.window, event.window === window else { return event }
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
