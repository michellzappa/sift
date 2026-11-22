import SwiftUI

/// The small network badge on Today's rows and cards (issue #41): the
/// network's symbol and name, quiet. The theme is the headline, the network
/// a detail. Compiled into the Mac app and the phone.
struct NetworkBadge: View {
    let network: LinkNetwork
    /// Over a picture (Watch cards): on a material capsule.
    var onImage = false

    var body: some View {
        Label(network.name, systemImage: network.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(onImage ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .lineLimit(1)
            .padding(.horizontal, onImage ? 7 : 5).padding(.vertical, onImage ? 3 : 1)
            .background {
                if onImage {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(Color.secondary.opacity(0.12))
                }
            }
            .fixedSize()
    }
}

/// A theme's section header in Today: a dot and the name in the theme's
/// colour.
struct ThemeSectionHeader: View {
    let title: String
    let color: Color
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.headline).foregroundStyle(color)
            if let count { Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            Spacer(minLength: 0)
        }
        .textCase(nil)
    }
}
