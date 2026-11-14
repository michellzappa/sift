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
    @AppStorage("links.style") private var linkStyle: LinkStyle = .list
    /// Where the sidebar was before a theme was focused.
    @State private var returnTo: SidebarItem?
    /// A link to another theme it also feeds: leaf index, theme hub index.
    @State private var crossEdges: [(Int, Int)] = []
    @State private var panBase: CGSize?
    @State private var pinchBase: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    private static let chip = CGSize(width: 196, height: 54)

    var body: some View {
        GeometryReader { geo in
            // The browser slides in over the right side; the graph and the
            // card grid underneath keep their size and position.
            ZStack(alignment: .trailing) {
                canvas(size: geo.size)
                    .onChange(of: linkStyle) { if let t = focusTheme { focus(t, size: geo.size) } }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                if let url = picked, let tab = model.tabs.first(where: { $0.url == url }) ?? model.archivedTabs.first(where: { $0.url == url }) {
                    WebPane(tab: tab) { withAnimation(.snappy) { picked = nil } }
                        .frame(width: BrowserOverlay.width(for: geo.size.width))
                        .background(.background)
                        .overlay(alignment: .leading) { Divider() }
                        .shadow(color: .black.opacity(0.12), radius: 12, x: -2)
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
        // Overview or a source picked in the sidebar: zoom back out.
        .onChange(of: selection) { _, new in
            switch new {
            case .overview, .source, nil: if focusTheme != nil { zoomOut() }
            default: break
            }
        }
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
            let theme = focusTheme ?? hover.flatMap { sim.nodes.indices.contains($0) ? sim.nodes[$0].theme : nil }
            if cam.fade(to: theme) { redraw += 1 }
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
        let shift = linkStyle == .list ? Self.panelWidth(size) / 2 : 0
        cam.animate(to: CGSize(width: -p.x * target + shift, height: -p.y * target), scale: target)
        withAnimation(.easeOut(duration: 0.3)) { focusTheme = theme }
        redraw += 1
        // The sidebar selects the theme too.
        if model.themes.contains(where: { $0.name == theme }) || Project.buckets.contains(theme) {
            if case .project = selection {} else { returnTo = selection }
            model.graphTheme = theme
            selection = .project(theme)
        }
    }

    private func unfocus() {
        zoomOut()
        if case .project = selection {
            model.graphTheme = nil
            selection = returnTo ?? .overview
        }
    }

    /// Back to all themes without touching the sidebar.
    private func zoomOut() {
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
        // Hover and focus fade in and out over a few frames (see GraphCamera).
        let lit = cam.fadeTheme
        let f = Double(cam.fade)
        func blend(_ normal: Double, _ dimmed: Double, _ isDim: Bool) -> Double { isDim ? normal + (dimmed - normal) * f : normal }
        let dotScale = max(0.7, min(cam.scale, 2.2))
        // Focused: the theme's own links are drawn as cards, not dots.
        // In the list layout the cluster stays visible beside the list.
        let hidden: (GraphSimulation.Node) -> Bool = { n in
            linkStyle == .grid && focusTheme != nil && n.theme == focusTheme && n.kind != .theme
        }

        for e in sim.edges {
            let a = sim.nodes[e.a], b = sim.nodes[e.b]
            if hidden(b) { continue }
            let pa = screen(a.p, size: size), pb = screen(b.p, size: size)
            var path = Path(); path.move(to: pa); path.addLine(to: pb)
            let bridge = a.kind == .theme && b.kind == .theme
            let dim = lit != nil && b.theme != lit && !(bridge && a.theme == lit)
            let opacity: Double
            if bridge {
                opacity = dim ? blend(0.16, 0.04, true) : (lit != nil ? 0.16 + (0.5 - 0.16) * f : 0.16)
            } else {
                opacity = blend(b.kind == .leaf ? 0.4 : 0.6, 0.07, dim)
            }
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [a.color.opacity(opacity), b.color.opacity(opacity)]), startPoint: pa, endPoint: pb),
                       lineWidth: (b.kind == .leaf ? 0.7 : b.kind == .group ? 1.1 : 1.2) * dotScale)
        }
        // A link that feeds a second theme: a faint line to that theme's hub,
        // brighter when either theme is lit.
        for (l, t) in crossEdges where sim.nodes.indices.contains(l) && sim.nodes.indices.contains(t) {
            let leaf = sim.nodes[l], hub = sim.nodes[t]
            if hidden(leaf) { continue }
            let pa = screen(leaf.p, size: size), pb = screen(hub.p, size: size)
            var path = Path(); path.move(to: pa); path.addLine(to: pb)
            let on = lit != nil && (leaf.theme == lit || hub.theme == lit)
            let opacity = lit == nil ? 0.1 : (on ? 0.1 + 0.35 * f : blend(0.1, 0.02, true))
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [leaf.color.opacity(opacity), hub.color.opacity(opacity)]), startPoint: pa, endPoint: pb),
                       style: StrokeStyle(lineWidth: 0.7 * dotScale, dash: [3, 3]))
        }
        for n in sim.nodes where !hidden(n) {
            let dim = lit != nil && n.theme != lit
            let p = screen(n.p, size: size)
            let r = n.size * dotScale
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            let shade = GraphicsContext.Shading.color(n.color.opacity(blend(n.kind == .leaf ? 0.75 : 1, 0.18, dim)))
            if n.hollow {
                ctx.stroke(dot, with: shade, lineWidth: max(0.6, 0.45 * dotScale))
            } else {
                ctx.fill(dot, with: shade)
            }
        }
        for (i, n) in sim.nodes.enumerated() where n.kind == .theme {
            let dim = lit != nil && n.theme != lit
            let p = screen(n.p, size: size)
            let focused = n.key == focusTheme
            let below = focused ? n.size * dotScale : sim.clusterRadius(i) * cam.scale
            _ = below
            // The title sits on the node's center, on a pill so it reads over the dots.
            let text = Text(n.label).font(.system(size: focused ? 15 : 11.5, weight: .semibold)).foregroundStyle(n.color.opacity(blend(1, 0.3, dim)))
            let size = ctx.resolve(text).measure(in: CGSize(width: 400, height: 40))
            let box = CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height)
            let pill = Path(roundedRect: box.insetBy(dx: -8, dy: -3), cornerRadius: (size.height + 6) / 2)
            ctx.fill(pill, with: .color(Color(nsColor: .textBackgroundColor).opacity(blend(0.94, 0.6, dim))))
            ctx.stroke(pill, with: .color(n.color.opacity(blend(0.45, 0.12, dim))), lineWidth: 1)
            ctx.draw(text, in: box)
        }
    }

    // MARK: Cards around the focused theme

    /// Every link of the focused theme as a card, in a grid that fits the
    /// view and scrolls when the theme is large, so no card hides another.
    static func panelWidth(_ size: CGSize) -> CGFloat { min(460, max(320, size.width * 0.4)) }

    @ViewBuilder
    private func chips(theme: String, node: Int, size: CGSize) -> some View {
        if linkStyle == .list { panel(theme: theme, node: node, size: size) } else { grid(theme: theme, node: node, size: size) }
    }

    /// The theme's links as a list in a panel on the left; the cluster stays
    /// in view on the right.
    private func panel(theme: String, node: Int, size: CGSize) -> some View {
        let tabs = links(in: theme)
        let color = sim.nodes[node].color
        let fade = min(1.0, max(0.0, Double(cam.scale - 1.1) / 0.6))
        return HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ThemeHeader(theme: theme, color: color, count: tabs.count)
                    LazyVStack(spacing: 2) {
                        ForEach(tabs) { tab in chipCell(tab, color: color) }
                    }
                    .padding(.horizontal, -8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 52)
                .padding(.bottom, 16)
            }
            .frame(width: Self.panelWidth(size), height: size.height)
            .background(.regularMaterial)
            .overlay(alignment: .trailing) { Divider() }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
        .opacity(fade)
    }

    private func grid(theme: String, node: Int, size: CGSize) -> some View {
        let tabs = links(in: theme)
        let color = sim.nodes[node].color
        let fade = min(1.0, max(0.0, Double(cam.scale - 1.1) / 0.6))
        let columns = [TabCard.column]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ThemeHeader(theme: theme, color: color, count: tabs.count)
                    .frame(maxWidth: 720, alignment: .leading)
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
        TabCard(tab: tab, isSelected: picked == tab.url, showTheme: false, style: linkStyle)
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

    /// Key of the old unsorted cluster; the graph no longer shows it.
    static let unsortedKey = "Not in a Theme Yet"

    private var themeNames: [String] {
        // Links in no theme yet stay off the graph: they show under Unsorted.
        model.projects.map(\.name).filter { model.count($0) > 0 }
    }

    /// The links behind a cluster; the unsorted cluster holds unsorted links.
    private func links(in name: String) -> [SafariTab] {
        name == Self.unsortedKey ? model.tabs(in: nil) : model.tabs(in: name)
    }

    private func color(for theme: String) -> Color {
        model.themeColor(theme)
    }

    /// Hosts too general to say two themes are related.
    private static let genericHosts: Set<String> = [
        "x.com", "twitter.com", "youtube.com", "m.youtube.com", "youtu.be", "reddit.com", "old.reddit.com",
        "threads.com", "threads.net", "linkedin.com", "google.com", "t.co", "medium.com", "substack.com",
    ]

    /// Builds the graph: themes joined to each other where they share sources
    /// or links, and a leaf per link around its theme, newest closest.
    private func rebuild() {
        var nodes: [GraphSimulation.Node] = []
        var edges: [GraphSimulation.Edge] = []
        for name in themeNames {
            // Newest links sit closest to the theme, oldest at the edge.
            let tabs = links(in: name).sorted { ($0.lastViewed ?? .distantPast) > ($1.lastViewed ?? .distantPast) }
            let tint = color(for: name)
            let t = nodes.count
            let size = 5 + sqrt(CGFloat(tabs.count)) * 0.8
            nodes.append(.init(kind: .theme, key: name, label: name, theme: name, color: tint, size: size, count: tabs.count))
            for (k, tab) in tabs.enumerated() {
                let angle = Double(k) * 2.399963
                let r = Double(size) + 7 + 6.2 * sqrt(Double(k) + 1)
                var leaf = GraphSimulation.Node(kind: .leaf, key: tab.url, label: "", theme: name, color: tint, size: 1.9, count: 1)
                leaf.anchor = t
                leaf.local = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
                // Solid: Sift saved its text or transcript. Hollow: only the title.
                let e = model.library[tab.url]
                leaf.hollow = !(e?.transcript == true || (e?.status == "ok" && (e?.words ?? 0) > 0))
                let i = nodes.count
                nodes.append(leaf)
                edges.append(.init(a: t, b: i, length: 0))
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
        // Links that feed two themes (Claude's connections) count three times
        // as much as a shared site.
        var linked: [String: Int] = [:]
        for a in model.state.assignments.values {
            for other in a.also ?? [] where themeNode[other] != nil && themeNode[a.project] != nil {
                linked[[a.project, other].sorted().joined(separator: "|"), default: 0] += 1
            }
        }
        let names = Array(themeNode.keys).sorted()
        for (x, a) in names.enumerated() {
            for b in names[(x + 1)...] {
                let shared = (sources[a] ?? []).intersection(sources[b] ?? []).count + 3 * (linked[a + "|" + b] ?? 0)
                guard shared > 0, let ia = themeNode[a], let ib = themeNode[b] else { continue }
                edges.append(.init(a: ia, b: ib, length: max(30, 150 - CGFloat(shared) * 30), weight: shared))
            }
        }
        sim.load(nodes: nodes, edges: edges)
        var cross: [(Int, Int)] = []
        for (i, n) in nodes.enumerated() where n.kind == .leaf {
            for other in model.state.assignments[n.key]?.also ?? [] {
                if let t = themeNode[other] { cross.append((i, t)) }
            }
        }
        crossEdges = cross
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
        // System backgrounds: white in light mode, macOS's neutral grey in dark.
        AnyShapeStyle(Color(nsColor: scheme == .dark ? .underPageBackgroundColor : .textBackgroundColor))
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

// MARK: - Simulation


/// Where the canvas looks and how close. Kept out of SwiftUI state so it
/// can glide every frame without rebuilding the view tree.
@MainActor
final class GraphCamera {
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    private var target: (offset: CGSize, scale: CGFloat)?

    /// The theme that stays bright while the others fade, and how far the
    /// fade has gone (0 = all bright, 1 = others dimmed).
    private(set) var fadeTheme: String?
    private(set) var fade: CGFloat = 0
    private var fadeTarget: CGFloat = 0
    private var pendingTheme: String?

    var isAnimating: Bool { target != nil || abs(fade - fadeTarget) > 0.01 || pendingTheme != fadeTheme }

    /// Starts a fade toward `theme` (nil: everything bright). A change of
    /// theme first fades back out, then in again. Returns true if it changed.
    func fade(to theme: String?) -> Bool {
        guard theme != pendingTheme else { return false }
        pendingTheme = theme
        if fadeTheme == nil { fadeTheme = theme }
        fadeTarget = theme == nil || theme != fadeTheme ? 0 : 1
        return true
    }

    func center(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
    }

    func animate(to offset: CGSize, scale: CGFloat) { target = (offset, scale) }

    /// About 120 ms each way at 60 fps.
    private func stepFade() {
        fade += (fadeTarget - fade) * 0.3
        if abs(fadeTarget - fade) < 0.01 { fade = fadeTarget }
        // Faded out: switch to the next theme and fade it in.
        if fade == 0, fadeTheme != pendingTheme {
            fadeTheme = pendingTheme
            fadeTarget = pendingTheme == nil ? 0 : 1
        }
    }

    func stop() { target = nil }

    /// Eases a little closer to the target each frame.
    func step() {
        stepFade()
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
        /// Links Sift has saved no text for are drawn as rings.
        var hollow = false

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
