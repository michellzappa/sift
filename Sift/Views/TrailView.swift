import SwiftUI

/// A trail: More Like This from one item (Engine/Trail.swift). The same list
/// and reader as Today. It ends; More Like This on any item in it starts a
/// new trail from there.
struct TrailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let trail = model.trail {
            OfferedList(picks: trail.picks, header: header(trail),
                        empty: ContentUnavailableView("Nothing near this yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                                      description: Text("Sift found no unseen item from the same creator or theme, or with words in common. Save or follow more around it.")))
                .navigationTitle("Trail")
                .navigationSubtitle("\(trail.picks.count) items")
                .toolbar {
                    ToolbarItem(placement: .principal) { ModePicker() }
                    ToolbarItem {
                        Button {
                            model.trail = nil
                            model.navigationRequest = .today
                        } label: { Label("End Trail", systemImage: "xmark.circle") }
                            .help("Close this trail")
                    }
                }
        } else {
            ContentUnavailableView("No trail", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                   description: Text("Choose More Like This on any item, or press T."))
        }
    }

    private func header(_ trail: TrailState) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("More like").font(.caption).foregroundStyle(.secondary)
                Text(trail.seed.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(rules).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let name = trail.seed.creatorName, !name.isEmpty {
                if trail.followed {
                    Label("Following \(name)", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Button("Follow \(name)") { model.followTrailCreator() }
                        .help("Follow this creator's feed. Its new posts can then reach Today.")
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var rules: String {
        "Same creator counts 3, same theme 1.5, closeness in meaning up to 3 (on this Mac), else 0.6 per shared word. Unseen only, at most \(Trail.perCreator) per creator, \(Trail.size) in all."
    }
}
