import SwiftUI

/// Overview: one hub per project, one dot per tab around its hub.
/// Hub size follows the tab count. Click a hub to open its list.
struct NetworkView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    @State private var hover: Hub?

    struct Hub: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let item: SidebarItem
        let count: Int
        var center: CGPoint = .zero
        var radius: CGFloat = 0
        let tint: Color
    }

    private static let dotSpacing: CGFloat = 7
    private static let dotSize: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let hubs = layout(in: geo.size)
            ZStack {
                Canvas { ctx, _ in
                    for hub in hubs {
                        let ring = Path(ellipseIn: CGRect(x: hub.center.x - hub.radius, y: hub.center.y - hub.radius, width: hub.radius * 2, height: hub.radius * 2))
                        ctx.fill(ring, with: .color(hub.tint.opacity(hover == hub ? 0.18 : 0.08)))
                        let scale = hub.radius / Self.hubRadius(hub.count)
                        for i in 0..<hub.count {
                            let p = Self.spiral(i, scale: scale)
                            let d = Self.dotSize * min(1, max(0.6, scale))
                            let rect = CGRect(x: hub.center.x + p.x - d / 2, y: hub.center.y + p.y - d / 2, width: d, height: d)
                            ctx.fill(Path(ellipseIn: rect), with: .color(hub.tint.opacity(0.85)))
                        }
                    }
                }
                ForEach(hubs) { hub in
                    VStack(spacing: 0) {
                        Text(hub.name).font(.caption.weight(.semibold))
                        Text("\(hub.count)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .position(x: hub.center.x, y: hub.center.y + hub.radius + 14)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase { hover = hubs.first { $0.center.distance(to: p) <= $0.radius + 6 } } else { hover = nil }
            }
            .onTapGesture { p in
                if let hub = hubs.first(where: { $0.center.distance(to: p) <= $0.radius + 6 }) { selection = hub.item }
            }
        }
        .padding(24)
        .navigationTitle("Overview")
        .navigationSubtitle("\(model.tabs.count) tabs · \(model.activeProjects.count) projects")
        .overlay {
            if model.tabs.isEmpty { ContentUnavailableView("No tabs on this device", systemImage: "safari") }
        }
    }

    // MARK: Layout

    private func layout(in size: CGSize) -> [Hub] {
        var hubs: [Hub] = model.activeProjects.enumerated().map { index, item in
            Hub(name: item.project, item: .project(item.project), count: item.count, tint: Self.palette[index % Self.palette.count])
        }
        if model.unsortedCount > 0 {
            hubs.append(Hub(name: "unsorted", item: .unsorted, count: model.unsortedCount, tint: .gray))
        }
        for bucket in Project.buckets where model.count(bucket) > 0 {
            hubs.append(Hub(name: bucket, item: .project(bucket), count: model.count(bucket), tint: .secondary))
        }
        hubs.sort { $0.count > $1.count }
        guard !hubs.isEmpty, size.width > 0, size.height > 0 else { return [] }

        // Greedy packing: walk a spiral out from the middle and take the first
        // spot where the hub clears every placed hub, with room for its label.
        let gap: CGFloat = 34
        var placed: [Hub] = []
        for var hub in hubs {
            hub.radius = Self.hubRadius(hub.count)
            var t: CGFloat = 0
            while true {
                let candidate = CGPoint(x: cos(t) * t * 3, y: sin(t) * t * 2)
                if placed.allSatisfy({ $0.center.distance(to: candidate) >= $0.radius + hub.radius + gap }) {
                    hub.center = candidate
                    break
                }
                t += 0.05
            }
            placed.append(hub)
        }

        // Fit the whole drawing into the view.
        let minX = placed.map { $0.center.x - $0.radius }.min()!
        let maxX = placed.map { $0.center.x + $0.radius }.max()!
        let minY = placed.map { $0.center.y - $0.radius }.min()!
        let maxY = placed.map { $0.center.y + $0.radius + 28 }.max()!
        let scale = min(size.width / max(1, maxX - minX), size.height / max(1, maxY - minY), 1.6)
        let offsetX = (size.width - (maxX - minX) * scale) / 2
        let offsetY = (size.height - (maxY - minY) * scale) / 2
        return placed.map { hub in
            var h = hub
            h.center = CGPoint(x: (hub.center.x - minX) * scale + offsetX, y: (hub.center.y - minY) * scale + offsetY)
            h.radius = hub.radius * scale
            return h
        }
    }

    /// Sunflower spiral: even spacing for any number of dots.
    private static func spiral(_ i: Int, scale: CGFloat) -> CGPoint {
        let angle = Double(i) * 2.399963 // golden angle
        let r = dotSpacing * scale * sqrt(Double(i) + 0.5)
        return CGPoint(x: cos(angle) * r, y: sin(angle) * r)
    }

    private static func hubRadius(_ count: Int) -> CGFloat {
        dotSpacing * sqrt(CGFloat(count) + 0.5) + 8
    }

    private static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo, .mint, .brown, .cyan, .yellow]
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
