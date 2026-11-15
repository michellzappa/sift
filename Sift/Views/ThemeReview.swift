import SwiftUI

/// Shows the themes Claude found, so the user can rename them, leave some
/// out, and accept. Nothing changes until "Use These Themes".
struct ThemeReview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    private var additive: Bool { model.themeProposalAdditive }

    struct Row: Identifiable {
        let id = UUID()
        var proposal: Sorter.ThemeProposal
        var include = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(additive ? "New themes for unsorted links" : "Themes in your links").font(.title2.weight(.semibold))
                Text(additive
                     ? "Claude read \(model.proposalURLs.count) links that are in no theme. Your current themes stay as they are. New themes come first: rename any, untick the ones you do not want. Below them, the links that fit a theme you have. Unticked links stay unsorted. \"errands\", \"personal\" and \"noise\" go to their buckets."
                     : "Claude read \(model.proposalURLs.count) links and found these themes. Rename any theme, untick the ones you do not want, then use them. Links in an unticked theme become unsorted. \"errands\", \"personal\" and \"noise\" go to their buckets.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            List($rows) { $row in
                HStack(alignment: .top, spacing: 12) {
                    Toggle("", isOn: $row.include).labelsHidden()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if row.proposal.kind == "existing" {
                                Text(row.proposal.name).font(.headline)
                            } else {
                                TextField("Name", text: $row.proposal.name)
                                    .textFieldStyle(.plain)
                                    .font(.headline)
                            }
                            Spacer()
                            Text(additive && row.proposal.kind != "existing" && !["noise", "personal", "errand"].contains(row.proposal.kind) ? "new" : row.proposal.kind)
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(row.proposal.itemIDs.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Text(row.proposal.description).font(.callout).foregroundStyle(.secondary)
                        if !row.proposal.destination.isEmpty {
                            Label(row.proposal.destination, systemImage: "arrow.turn.down.right")
                                .font(.caption).foregroundStyle(.tint)
                                .help(row.proposal.why)
                        }
                        Text(examples(row.proposal)).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
                .opacity(row.include ? 1 : 0.5)
            }

            HStack {
                Text("\(rows.filter(\.include).count) of \(rows.count) themes").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.themeProposal = nil; model.themeProposalAdditive = false; dismiss() }
                Button(additive ? "Add Themes and Sort" : "Use These Themes") {
                    if additive {
                        model.applyNewThemes(rows.filter(\.include).map(\.proposal))
                    } else {
                        model.applyThemes(rows.filter(\.include).map(\.proposal))
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!rows.contains(where: \.include))
            }
            .padding(20)
        }
        .frame(width: 680, height: 640)
        .onAppear { rows = (model.themeProposal ?? []).map { Row(proposal: $0) } }
    }

    /// The first few link titles in a theme, so the name can be checked.
    private func examples(_ p: Sorter.ThemeProposal) -> String {
        p.itemIDs.prefix(4).compactMap { id -> String? in
            guard model.proposalURLs.indices.contains(id) else { return nil }
            let url = model.proposalURLs[id]
            let tab = model.tabs.first { $0.url == url }
            let preview = model.previews[url]
            if let tab, tab.hasUsefulTitle { return tab.title }
            if let preview, !preview.failed, !preview.title.isEmpty { return preview.site == "x.com" ? String(preview.text.prefix(60)) : preview.title }
            return URL(string: url)?.host() ?? url
        }
        .map { String($0.prefix(60)) }
        .joined(separator: " · ")
    }
}
