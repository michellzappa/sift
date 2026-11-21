import SwiftUI

/// The header above a theme's links: the name and the List/Grid toggle on
/// one line, the summary, then one quiet line with the link count, where the
/// theme's links are sent, and its history.
struct ThemeHeader: View {
    @Environment(AppModel.self) private var model
    let theme: String
    var color: Color = .primary
    var count: Int
    /// Off in lists, where the window title already names the theme.
    var showTitle = true
    @State private var showHistory = false

    var body: some View {
        let project = model.projects.first { $0.name == theme }
        VStack(alignment: .leading, spacing: 6) {
            if showTitle {
                HStack(alignment: .center) {
                    Text(theme).font(.title3.weight(.semibold)).foregroundStyle(color)
                    Spacer(minLength: 8)
                }
                if let summary = project?.summary, !summary.isEmpty {
                    Text(summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Text("\(count) links")
                if project?.isTheme == true { sendsTo(project) }
                Spacer(minLength: 0)
                if let history = project?.history, !history.isEmpty {
                    Button { showHistory.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .buttonStyle(.borderless)
                        .help("History of this theme")
                        .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(history.reversed(), id: \.self) { Text($0) }
                            }
                            .font(.caption)
                            .padding(12)
                        }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let terms = model.themeTerms[theme], !terms.isEmpty {
                // Subterms: what sets this theme apart, counted on this Mac.
                Text(terms.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                    .help("The words that set this theme apart from your other themes, from the titles and previews of its links.")
            }
            if let parts = model.subClusters[theme], parts.count >= 2 { SubClusterChips(theme: theme, parts: parts) }
            if project?.isTheme == true { ThemeDialRow(theme: theme) }
        }
    }

    /// "Sends to" as a quiet menu, and a button for the links not sent yet.
    @ViewBuilder
    private func sendsTo(_ project: Project?) -> some View {
        if !model.destinations.isEmpty {
            let current = model.destination(project?.sendTo)
            Text("·").foregroundStyle(.tertiary)
            Menu {
                ForEach(model.destinations) { d in
                    Button { model.setDefaultDestination(d.id, forTheme: theme) } label: {
                        Label { Text(d.name) } icon: { current?.id == d.id ? Image(systemName: "checkmark") : d.image }
                    }
                }
                if current != nil {
                    Divider()
                    Button("Nowhere") { model.setDefaultDestination(nil, forTheme: theme) }
                }
            } label: {
                Text(current.map { "Sends to \($0.name)" } ?? "Choose where to send")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Where one click on a link's plane sends it.")
            if let d = current {
                let unsent = model.tabs(in: theme).filter { tab in !model.sentRecords(tab.url).contains { $0.destination == d.id } }
                if !unsent.isEmpty {
                    Button("Send \(unsent.count)") { Task { await model.send(unsent, to: d) } }
                        .buttonStyle(.borderless)
                        .help("Sends the links in this theme that have not gone to \(d.name) yet.")
                }
            }
        }
    }
}

/// The parts of a theme by meaning (Engine/SubClusters.swift) as chips.
/// A chip narrows the theme's list to that part; All, or the chip again,
/// shows every link.
struct SubClusterChips: View {
    @Environment(AppModel.self) private var model
    let theme: String
    let parts: [SubCluster]

    var body: some View {
        let current = model.subClusterFilter?.theme == theme ? model.subClusterFilter?.name : nil
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", on: current == nil) { model.subClusterFilter = nil }
                ForEach(parts) { part in
                    chip("\(part.name) (\(part.size))", on: current == part.name) {
                        model.subClusterFilter = current == part.name ? nil : SubClusterFilter(theme: theme, name: part.name)
                    }
                }
            }
        }
        .help("The parts of this theme, grouped by meaning on this Mac. Click one to show only its links.")
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// The theme's dial (Engine/Dials.swift) and the sources Sift is trying for it.
struct ThemeDialRow: View {
    @Environment(AppModel.self) private var model
    let theme: String

    var body: some View {
        let dial = model.dial(of: theme)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("In Today").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { dial }, set: { model.setDial($0, for: theme) })) {
                    ForEach(ThemeDial.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                Text(dial.help).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
            }
            ForEach(model.trialFeeds(for: theme)) { f in
                HStack(spacing: 6) {
                    Image(systemName: "flask").foregroundStyle(.secondary).font(.caption)
                    Text("Trying \(f.title)").font(.caption).lineLimit(1)
                    if let s = f.trialSource { Text("· \(s)").font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                    if let until = f.trialUntil {
                        Text("· until \(until.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 4)
                    Button("Follow") { model.followTrial(f) }.controlSize(.mini)
                    Button("Stop") { model.stopTrial(f) }.controlSize(.mini)
                }
            }
        }
    }
}
