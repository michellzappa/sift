import SwiftUI

/// Your Graph: the creators behind what you saved (Feeds/Creators.swift).
/// Sift shows the numbers and proposes; you follow, or hide. A creator
/// reaches Today only after you follow it.
struct CreatorsView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: Creator.Kind?
    @State private var theme: String?
    @State private var notFollowed = false
    @State private var showHidden = false
    @State private var filter = ""
    @State private var selected: String?
    @AppStorage("graph.tab") private var tab = "yours"

    private var shown: [Creator] {
        let base = showHidden ? model.hiddenCreatorList : model.visibleCreators
        return base.filter { c in
            (kind == nil || c.kind == kind)
                && (theme == nil || c.themes.contains { $0.name == theme })
                && (!notFollowed || c.feedID == nil)
                && (filter.isEmpty || c.name.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Your Graph").tag("yours")
                Text("Next Door").tag("nextdoor")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.vertical, 8)
            Divider()
            if tab == "nextdoor" { NextDoorView() } else { yours }
        }
        .navigationTitle("Your Graph")
        .onAppear { if model.creators.isEmpty { model.refreshCreators() } }
    }

    private var yours: some View {
        ReaderSplit(showing: shown.contains { $0.id == selected }) {
            VStack(spacing: 0) {
                header
                Divider()
                if shown.isEmpty {
                    ContentUnavailableView(model.creators.isEmpty ? "No creators yet" : "Nothing matches",
                                           systemImage: "person.2",
                                           description: Text(model.creators.isEmpty
                                                             ? "Your Graph needs at least \(Creators.minSaves) saved links from the same channel, site or community."
                                                             : "Change the filters above."))
                } else {
                    List(shown, selection: $selected) { c in
                        CreatorRow(creator: c).tag(c.id)
                            .contextMenu { menu(c) }
                    }
                    .listStyle(.inset)
                }
            }
        } pane: {
            if let c = shown.first(where: { $0.id == selected }) {
                CreatorPane(creator: c).id(c.id)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The channels, writers and communities behind what you saved. Score = your saves from them, each counted by age: a save counts half after \(Int(Creators.halfLifeDays)) days. Sift only proposes. A creator reaches Today only after you follow it, and Your Graph gives its new posts a lift there.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Picker("", selection: $kind) {
                    Text("All").tag(Creator.Kind?.none)
                    ForEach(Creator.Kind.allCases, id: \.self) { Text($0.label).tag(Creator.Kind?.some($0)) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("", selection: $theme) {
                    Text("All Themes").tag(String?.none)
                    ForEach(model.themes.map(\.name), id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden().fixedSize()
                Toggle("Not followed", isOn: $notFollowed).toggleStyle(.checkbox)
                Toggle("Hidden", isOn: $showHidden).toggleStyle(.checkbox)
                Spacer()
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
            }
            .controlSize(.small)
            Text("\(shown.count) creators · \(model.visibleCreators.filter { $0.feedID != nil }.count) followed")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    @ViewBuilder private func menu(_ c: Creator) -> some View {
        if c.feedID == nil {
            Button("Follow \(c.name)") { model.followCreator(c) }
        } else {
            Button("Unfollow \(c.name)") { model.unfollowCreator(c) }
        }
        Button(showHidden ? "Show in Your Graph" : "Hide") { model.setCreatorHidden(c, !showHidden) }
    }
}

private struct CreatorRow: View {
    let creator: Creator

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: creator.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(creator.name).fontWeight(.medium).lineLimit(1)
                    if creator.feedID != nil {
                        Text("Following").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.1f", creator.score)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .help("Score: saves counted by age")
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = ["\(creator.count) saved"]
        if creator.recent > 0 { parts.append("\(creator.recent) in 90 days") }
        if let last = creator.lastSaved { parts.append("last " + last.formatted(.relative(presentation: .named))) }
        if let t = creator.themes.first { parts.append(t.name) }
        return parts.joined(separator: " · ")
    }
}

private struct CreatorPane: View {
    @Environment(AppModel.self) private var model
    let creator: Creator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(creator.kind.label, systemImage: creator.kind.symbol).font(.caption).foregroundStyle(.secondary)
                    Text(creator.name).font(.title2.weight(.semibold))
                }
                HStack {
                    if creator.feedID == nil {
                        Button("Follow") { model.followCreator(creator) }.buttonStyle(.borderedProminent)
                    } else {
                        Label("Following", systemImage: "checkmark").foregroundStyle(.tint)
                        Button("Unfollow") { model.unfollowCreator(creator) }
                    }
                    let hidden = model.state.hiddenCreators.contains(creator.id)
                    Button(hidden ? "Show in Your Graph" : "Hide") { model.setCreatorHidden(creator, !hidden) }
                }
                score
                if !creator.themes.isEmpty { themes }
                saves
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var score: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Why it is here").font(.headline)
            Text(String(format: "Score %.2f: %d saves. A save from today counts 1, from %d days ago 0.5, from %d days ago 0.25. %d of the saves are from the last 90 days.",
                        creator.score, creator.count, Int(Creators.halfLifeDays), Int(Creators.halfLifeDays * 2), creator.recent))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if creator.feedID != nil {
                Text(String(format: "In Today, its new posts get + %.2f on their score.", TodayBuilder.creatorBonus(creator.count)))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(String(format: "If you follow it, its new posts get + %.2f on their score in Today.", TodayBuilder.creatorBonus(creator.count)))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var themes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In your themes").font(.headline)
            let top = creator.themes.first?.count ?? 1
            ForEach(creator.themes, id: \.name) { t in
                HStack(spacing: 8) {
                    Text(t.name).font(.callout).frame(width: 160, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.5))
                            .frame(width: max(4, g.size.width * Double(t.count) / Double(top)))
                    }
                    .frame(height: 8)
                    Text("\(t.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                }
            }
        }
    }

    private var saves: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What you saved").font(.headline)
            ForEach(creator.saves.prefix(40), id: \.url) { s in
                Button { model.openInApp(s.url) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title.isEmpty ? s.url : s.title).lineLimit(2).multilineTextAlignment(.leading)
                            Text([s.date.formatted(date: .abbreviated, time: .omitted), s.theme].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.2f", Creators.weight(s.date))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .help("What this save adds to the score")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if creator.count > 40 {
                Text("and \(creator.count - 40) more").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Next Door: creators outside your graph that two or more of yours link
/// to, with every link as evidence.
private struct NextDoorView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?
    @State private var theme: String?

    private var shown: [Neighbor] {
        model.visibleNeighbors.filter { theme == nil || $0.themes.contains { $0.name == theme } }
    }

    var body: some View {
        ReaderSplit(showing: shown.contains { $0.id == selected }) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Creators outside your graph that \(NextDoor.minLinkers) or more of yours link to: in pages and video descriptions you saved, and in the feeds you follow. Each creator who links adds 1 + log(1 + its own score), so a link from someone high in your graph counts more. Sponsor links, shops, tip jars and a creator's own site do not count. Sift reads only what is already on this Mac.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Picker("", selection: $theme) {
                            Text("All Themes").tag(String?.none)
                            ForEach(model.themes.map(\.name), id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        .labelsHidden().fixedSize()
                        Spacer()
                        if model.isFindingNeighbors {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Look Again") { Task { await model.refreshNeighbors(force: true) } }
                        }
                    }
                    .controlSize(.small)
                }
                .padding(12)
                Divider()
                if shown.isEmpty {
                    ContentUnavailableView(model.isFindingNeighbors ? "Reading your library…" : "Nobody next door yet",
                                           systemImage: "person.2.wave.2",
                                           description: Text("Next Door needs creators in your graph whose saved pages, descriptions or feed items link out."))
                } else {
                    List(shown, selection: $selected) { n in
                        NeighborRow(neighbor: n).tag(n.id)
                            .contextMenu {
                                Button("Follow \(n.name)") { model.followNeighbor(n) }
                                Button("Hide") { model.setNeighborHidden(n, true) }
                            }
                    }
                    .listStyle(.inset)
                }
            }
        } pane: {
            if let n = shown.first(where: { $0.id == selected }) { NeighborPane(neighbor: n).id(n.id) }
        }
        .task { if model.neighbors.isEmpty { await model.refreshNeighbors() } }
    }
}

private struct NeighborRow: View {
    let neighbor: Neighbor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: neighbor.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(neighbor.name).fontWeight(.medium).lineLimit(1)
                Text(NextDoorText.linkedBy(neighbor)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.1f", neighbor.score)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

enum NextDoorText {
    /// "Linked by Dwarkesh Patel, Lenny's Podcast and 2 more · 9 links"
    static func linkedBy(_ n: Neighbor) -> String {
        let names = n.linkedBy
        let head = names.prefix(2).joined(separator: ", ")
        let rest = names.count > 2 ? " and \(names.count - 2) more" : ""
        return "Linked by \(head)\(rest) · \(n.mentions) links"
    }
}

private struct NeighborPane: View {
    @Environment(AppModel.self) private var model
    let neighbor: Neighbor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Next Door · \(neighbor.kind.label)", systemImage: neighbor.kind.symbol).font(.caption).foregroundStyle(.secondary)
                    Text(neighbor.name).font(.title2.weight(.semibold))
                }
                HStack {
                    Button("Follow") { model.followNeighbor(neighbor) }.buttonStyle(.borderedProminent)
                    Button("Hide") { model.setNeighborHidden(neighbor, true) }
                    Button("Open Site") { model.openInApp(neighbor.input.hasPrefix("http") ? neighbor.input : "https://" + neighbor.input) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why it is here").font(.headline)
                    Text(String(format: "Score %.2f: %d creators in your graph link to it, %d times in all. Each adds 1 + log(1 + its own score).",
                                neighbor.score, neighbor.linkedBy.count, neighbor.mentions))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Linked by: " + neighbor.linkedBy.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                    if !neighbor.themes.isEmpty {
                        Text("Through your themes: " + neighbor.themes.prefix(4).map { "\($0.name) (\($0.count))" }.joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("The links").font(.headline)
                    ForEach(neighbor.evidence, id: \.self) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Button { model.openInApp(e.itemURL) } label: {
                                Text("\(e.from): \(e.item.isEmpty ? e.itemURL : e.item)").lineLimit(2).multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                            Button { model.openInApp(e.link) } label: {
                                Text(e.link).font(.caption).foregroundStyle(.tint).lineLimit(1).truncationMode(.middle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
