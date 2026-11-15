import SwiftUI

/// ⌘K: one floating panel to go anywhere, open a Settings pane, run an
/// action, follow a handle or find a link. Items and ranking are in
/// App/CommandPalette+Items.swift. ContentView shows it while
/// `AppModel.showPalette` is true.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var sections: [PaletteSection] = []
    @State private var hits: [SearchIndex.Hit] = []
    @State private var selected: String?
    @FocusState private var focused: Bool

    private static let rowHeight: CGFloat = 38
    private static let visibleRows: CGFloat = 12

    private var rows: [PaletteItem] { sections.flatMap(\.items) }

    var body: some View {
        ZStack(alignment: .top) {
            // A click outside the panel closes it.
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { close() }
            panel.padding(.top, 70)
        }
        .onAppear {
            rebuild()
            focused = true
        }
        // Instant matches at once; full-text hits after a short pause.
        .task(id: query) {
            hits = []
            rebuild()
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let found = await model.searchLibrary(q)
            guard !Task.isCancelled else { return }
            hits = Array(found.prefix(40))
            rebuild()
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                TextField("Go to a theme, feed, setting or link", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { if let item = rows.first(where: { $0.id == selected }) ?? rows.first { run(item) } }
                    .onKeyPress(.downArrow) { step(1); return .handled }
                    .onKeyPress(.upArrow) { step(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onExitCommand { close() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            if !sections.isEmpty || !query.isEmpty { Divider() }
            if sections.isEmpty, !query.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else if !sections.isEmpty {
                list
            }
        }
        .frame(width: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.section.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 3)
                        ForEach(section.items) { item in row(item).id(item.id) }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(height: listHeight)
            .onChange(of: selected) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    /// As tall as the rows, up to about twelve rows; then it scrolls.
    private var listHeight: CGFloat {
        let content = CGFloat(rows.count) * Self.rowHeight + CGFloat(sections.count) * 24 + 6
        return min(content, Self.rowHeight * Self.visibleRows)
    }

    private func row(_ item: PaletteItem) -> some View {
        let isSelected = item.id == selected
        return HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .frame(width: 20)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            Spacer(minLength: 12)
            if !item.hint.isEmpty {
                Text(item.hint)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { if $0 { selected = item.id } }
        .onTapGesture { run(item) }
    }

    // MARK: Behaviour

    private func rebuild() {
        sections = PaletteCatalog.results(query, hits: hits, model)
        // Keep the highlight on the same row when it is still there.
        if selected == nil || !rows.contains(where: { $0.id == selected }) { selected = rows.first?.id }
    }

    private func step(_ delta: Int) {
        let list = rows
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selected } ?? -delta
        selected = list[min(max(i + delta, 0), list.count - 1)].id
    }

    private func close() {
        model.showPalette = false
    }

    private func run(_ item: PaletteItem) {
        close()
        switch item.command {
        case .go, .settings: PaletteRecents.add(item.key)
        default: break
        }
        switch item.command {
        case .go(let place):
            model.navigationRequest = place
        case .settings(let pane):
            SettingsRoute.navigation.show(pane: pane)
            openSettings()
        case .followSheet:
            model.showAddFeed = true
        case .follow(let text):
            model.followQuick(text)
        case .reload:
            model.reload()
        case .checkFeeds:
            Task { await model.fetchFeeds(force: true) }
        case .newToday:
            model.refreshToday(force: true)
            model.navigationRequest = .today
        case .discover:
            Task { await model.discoverThemes() }
        case .sort:
            Task { await model.sortUnsorted() }
        case .export(let id):
            if let exporter = Exporters.all.first(where: { $0.id == id }) { model.runExport(exporter) }
        case .updates:
            Task { await UpdateChecker.shared.checkFromMenu() }
        case .versionHistory:
            openWindow(id: VersionHistory.windowID)
        case .setupGuide:
            model.startSetupGuide()
            openWindow(id: Onboarding.windowID)
        case .link(let url, let place):
            model.navigationRequest = place
            // Sift's browser, not Safari: a Safari tab would come back as a link.
            model.openInApp(url)
        }
    }
}
