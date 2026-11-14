import AppKit
import CoreImage
import SwiftUI

/// The tabs in one sidebar item: unsorted, a project or bucket, or the close list.
struct TabList: View {
    @Environment(AppModel.self) private var model
    let item: SidebarItem
    @State private var search = ""
    @State private var selected: SafariTab.ID?
    @State private var showInspector = false
    @State private var showShortcutGuide = false
    @State private var siteFilter: String?
    /// A saved search's links, loaded from the search index.
    @State private var savedHits: [SafariTab] = []
    @AppStorage("links.style") private var style: LinkStyle = .list
    /// Full-text matches for the filter: url to snippet, from the search index.
    @State private var textHits: [String: String] = [:]

    private var project: String? {
        if case .project(let p) = item { return p }
        return nil
    }

    private var title: String {
        switch item {
        case .overview, .source: "Overview"
        case .unsorted: "Unsorted"
        case .closeQueue: "To close on iPhone"
        case .archive: "Archive"
        case .duplicates: "Duplicates"
        case .broken: "Broken Links"
        case .saved(let q): "“\(q)”"
        case .project(let p): Project.displayName(p)
        case .site(let host): host
        case .destination(let id): model.destination(id)?.name ?? "Destination"
        }
    }

    private var all: [SafariTab] {
        switch item {
        case .overview, .source: model.tabs
        case .unsorted: model.tabs(in: nil)
        case .closeQueue: model.closeQueueTabs
        case .archive: model.archivedTabs
        case .duplicates: model.duplicateTabs
        case .broken: model.brokenTabs
        case .saved: savedHits
        case .project(let p): model.tabs(in: p)
        case .site(let host): model.tabs(onSite: host)
        case .destination(let id): model.sentTabs(to: id)
        }
    }

    /// Sites in this list, for the site filter.
    private var listSites: [(host: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tab in all { counts[tab.host, default: 0] += 1 }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    private var rows: [SafariTab] {
        let base = siteFilter.map { host in all.filter { $0.host == host } } ?? all
        guard !search.isEmpty else { return base }
        return base.filter {
            textHits[$0.url] != nil
                || $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search)
                || (model.assignment(for: $0)?.use.localizedCaseInsensitiveContains(search) ?? false)
                || (model.previews[$0.url]?.text.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if item == .closeQueue { closeHeader }
            if item == .duplicates { duplicatesHeader }
            ScrollView {
                if let project, model.themes.contains(where: { $0.name == project }) {
                    ThemeHeader(theme: project, count: rows.count, showTitle: false).frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top], 16)
                }
                if style == .list {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { tab in
                            cell(tab).id(tab.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    // Rows stay clear of the browser pane, so none hides under it.
                    .padding(.trailing, showInspector ? BrowserOverlay.width(for: listWidth) : 0)
                } else {
                    LazyVGrid(columns: [TabCard.column], spacing: 14) {
                        ForEach(rows) { tab in cell(tab) }
                    }
                    .padding(16)
                }
            }
            .background(style == .list ? Color(nsColor: .textBackgroundColor) : Color(nsColor: .underPageBackgroundColor))
            .background(GeometryReader { g in Color.clear.onAppear { listWidth = g.size.width }.onChange(of: g.size.width) { _, w in listWidth = w } })
            .scrollPosition(id: $scrolledTo, anchor: .center)
            // Keyboard: arrows move, space opens or closes the browser.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1); return .handled }
            .onKeyPress(.upArrow) { step(-1); return .handled }
            .onKeyPress(.space) {
                guard selected != nil else { return .ignored }
                withAnimation(.snappy) { showInspector.toggle() }
                return .handled
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(item == .unsorted ? "Nothing left to sort" : "No tabs here", systemImage: "checkmark.circle")
            }
        }
        .searchable(text: $search, prompt: "Search titles, page text and transcripts")
        .task(id: item) {
            if case .saved(let q) = item { savedHits = await model.links(matching: q) }
        }
        .task(id: search) {
            guard search.count > 1 else { textHits = [:]; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let hits = await model.searchLibrary(search)
            textHits = Dictionary(hits.map { ($0.url, $0.snippet) }, uniquingKeysWith: { a, _ in a })
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        // The browser slides in over the right side. The grid underneath
        // keeps its size and position, so no card moves.
        .overlay(alignment: .trailing) {
            if showInspector, let tab = rows.first(where: { $0.id == selected }) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        WebPane(tab: tab) { withAnimation(.snappy) { showInspector = false } }
                            .frame(width: BrowserOverlay.width(for: geo.size.width))
                            .background(.background)
                            .overlay(alignment: .leading) { Divider() }
                            .shadow(color: .black.opacity(0.12), radius: 12, x: -2)
                    }
                }
                .transition(.move(edge: .trailing))
            }
        }
        .toolbar { listToolbar }
        .sheet(isPresented: $showShortcutGuide) { ShortcutGuide() }
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem { LinkStyleToggle() }
        ToolbarItem {
            Button { model.saveSearch(search) } label: { Label("Save Search", systemImage: "bookmark") }
                .disabled(search.count < 2 || model.state.savedSearches.contains(search))
                .help("Keep this search in the sidebar.")
        }
        ToolbarItemGroup {
            if listSites.count > 1 {
                Menu {
                    Button("All sites") { siteFilter = nil }
                    Divider()
                    ForEach(listSites.prefix(30), id: \.host) { s in
                        Button("\(s.host) (\(s.count))") { siteFilter = s.host }
                    }
                } label: {
                    Label(siteFilter ?? "All sites", systemImage: "globe")
                }
                .help("Show only tabs from one site.")
            }
            if model.fetchingPreviews > 0 {
                HStack(spacing: 4) { ProgressView().controlSize(.small); Text("\(model.fetchingPreviews)").monospacedDigit() }
            } else {
                Button { Task { await model.fetchPreviews(for: rows) } } label: {
                    Label("Fetch Previews", systemImage: "text.below.photo")
                }
                .help("Fetch the title, text and image of each tab in this list.")
            }
            if project == Project.unknown {
                Button { Task { await model.resortUnknown() } } label: {
                    Label("Fetch and Re-sort", systemImage: "wand.and.stars")
                }
                .help("Fetch previews for these tabs, then sort them again with the preview text.")
                .disabled(model.isSorting)
            }
            if item != .closeQueue, !rows.isEmpty, !model.isSavedList {
                Button { model.queueClose(rows) } label: {
                    Label("Close All on iPhone", systemImage: "xmark.square")
                }
                .help("Add every tab in this list to the close list for the iPhone Shortcut.")
            }
            if let project {
                Button { model.copy(model.markdown(for: project)) } label: {
                    Label("Copy as Markdown", systemImage: "doc.on.doc")
                }
                .help("Copy this project's links and uses as a Markdown list.")
            }
            Button { showInspector.toggle() } label: { Label("Browser", systemImage: "sidebar.right") }
        }
    }

    private var closeHeader: some View {
        HStack {
            Image(systemName: "iphone")
            if CloseList.iCloudDriveAvailable {
                Text("\(model.state.closeQueue.count) tabs wait in iCloud Drive/Sift/close.txt. Run the Sift Shortcut on the iPhone to close them.")
            } else {
                Text("iCloud Drive is off on this Mac, so the iPhone cannot read the close list.")
            }
            Spacer()
            Button("Set Up Shortcut…") { showShortcutGuide = true }
            Button("Clear") { model.unqueueClose(all) }.disabled(all.isEmpty)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    @State private var listWidth: CGFloat = 900
    @State private var scrolledTo: String?

    private func cell(_ tab: SafariTab) -> some View {
        TabCard(tab: tab, isSelected: selected == tab.id, showTheme: project == nil || Project.buckets.contains(project ?? ""), style: style)
            .onTapGesture(count: 2) { TabActions.openInSafari(tab.url) }
            .onTapGesture { withAnimation(.snappy) { selected = tab.id; showInspector = true } }
    }

    private var duplicatesHeader: some View {
        HStack {
            Text("Each page appears once per copy. Merge keeps one per page (the one you sorted, else the newest) and hides the rest. The kept link takes over their theme and note.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Merge All") { model.mergeDuplicates() }
        }
        .padding(12)
        .background(.bar)
    }

    private func step(_ by: Int) {
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { $0.id == selected }.map { min(max($0 + by, 0), rows.count - 1) } ?? 0
        selected = rows[i].id
        scrolledTo = rows[i].id
    }

    private var subtitle: String {
        let n = rows.count
        let text = model.projects.first(where: { $0.name == project })?.summary ?? ""
        return "\(n) tab\(n == 1 ? "" : "s")" + (text.isEmpty ? "" : " · \(text.prefix(80))")
    }
}

/// How lists show links: rows (the default) or cards.
enum LinkStyle: String {
    case list, grid
}

/// List or grid, remembered for every list and the graph's theme view.
struct LinkStyleToggle: View {
    @AppStorage("links.style") private var style: LinkStyle = .list

    var body: some View {
        Picker("Layout", selection: $style) {
            Image(systemName: "list.bullet").tag(LinkStyle.list).help("List")
            Image(systemName: "square.grid.2x2").tag(LinkStyle.grid).help("Grid")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// One tab as a row or a card: preview image, title, text, theme, action.
/// The card fetches its own preview when it scrolls into view.
struct TabCard: View {
    /// One fixed card width everywhere. When the browser opens, rows hold
    /// fewer cards; the cards themselves keep their size.
    static let width: CGFloat = 290
    static let column = GridItem(.adaptive(minimum: width, maximum: width), spacing: 14)

    @Environment(AppModel.self) private var model
    let tab: SafariTab
    let isSelected: Bool
    /// Off inside a theme's own list, where the theme would repeat on every card.
    var showTheme = true
    /// A row in the list, or a card in the grid.
    var style: LinkStyle = .list
    @State private var hovering = false
    @State private var editingNote = false
    @State private var noteDraft = ""
    @State private var editingUse = false
    @State private var draft = ""

    var body: some View {
        let a = model.assignment(for: tab)
        let preview = model.previews[tab.url]
        let closing = model.isQueuedToClose(tab)
        Group {
            if style == .list { row(a, preview, closing) } else { card(a, preview, closing) }
        }
        .contentShape(Rectangle())
        .task(id: tab.url) { await model.preview(for: tab) }
        .contextMenu {
            Button("Open in Safari") { TabActions.openInSafari(tab.url) }
            Button("Add to Reading List") {
                model.exportMessage = TabActions.addToReadingList(tab.url, title: cardTitle(preview), preview: bodyText(preview) ?? "")
            }
            Button("Copy Link") { model.copy(tab.url) }
            Button(model.note(for: tab.url) == nil ? "Add Note…" : "Edit Note…") {
                noteDraft = model.note(for: tab.url) ?? ""
                editingNote = true
            }
            if !model.destinations.isEmpty {
                Menu("Send to") {
                    ForEach(model.destinations) { d in
                        Button(d.name) { Task { await model.send(tab, to: d) } }
                    }
                }
            }
            Divider()
            if !model.isSavedList {
                Button(closing ? "Keep Open on iPhone" : "Close on iPhone") { model.toggleClose(tab) }
            }
            Menu("Move to") { moveMenu }
            Button("Mark as Noise") { model.move(tab, to: Project.drop) }
        }
        .popover(isPresented: $editingNote) {
            VStack(alignment: .leading) {
                Text("Your note on this link").font(.headline)
                TextField("What it taught you, why you kept it", text: $noteDraft, axis: .vertical).frame(width: 340).lineLimit(2...8)
                HStack {
                    Spacer()
                    Button("Cancel") { editingNote = false }
                    Button("Save") { model.setNote(noteDraft, for: tab.url); editingNote = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .popover(isPresented: $editingUse) {
            VStack(alignment: .leading) {
                Text("How could this link be used?").font(.headline)
                TextField("Use", text: $draft, axis: .vertical).frame(width: 340).lineLimit(2...5)
                HStack {
                    Spacer()
                    Button("Cancel") { editingUse = false }
                    Button("Save") { model.setUse(draft, for: tab); editingUse = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
    }

    // MARK: Row

    /// One link as a row: thumbnail, title, a meta line with one line of
    /// preview, then the theme and the next action. The text truncates, so a
    /// row fits any width.
    private func row(_ a: Assignment?, _ preview: Preview?, _ closing: Bool) -> some View {
        HStack(spacing: 12) {
            thumbnail(preview)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 3) {
                Text(cardTitle(preview))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .strikethrough(closing, color: .secondary)
                HStack(spacing: 5) {
                    Image(systemName: tab.sourceSymbol).help("From \(tab.source)")
                    Text(tab.host).lineLimit(1).fixedSize()
                    if let d = tab.lastViewed {
                        Text("·")
                        Text(d, format: Self.dateFormat(d)).fixedSize()
                    }
                    if let saved = savedSymbol {
                        Image(systemName: saved.symbol).help(saved.help)
                    }
                    if let text = bodyText(preview) ?? xText(preview) {
                        Text("·")
                        Text(text).lineLimit(1).foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = model.note(for: tab.url) {
                    Label(note, systemImage: "pencil.line").font(.caption).lineLimit(1).foregroundStyle(.primary.opacity(0.75))
                }
            }
            Spacer(minLength: 8)
            if a?.manual == true { Image(systemName: "hand.point.up.left").foregroundStyle(.tertiary).help("Sorted by hand") }
            if closing { Image(systemName: "xmark.square").foregroundStyle(.secondary).help("Closes on iPhone") }
            if let a {
                if showTheme {
                    Menu { moveMenu } label: {
                        HStack(spacing: 5) {
                            Circle().fill(model.themeColor(a.project)).frame(width: 7, height: 7)
                            Text(Project.displayName(a.project)).lineLimit(1)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 170, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Theme: \(a.project)")
                }
            }
            let sent = !model.sentRecords(tab.url).isEmpty
            SendButton(tab: tab, compact: true)
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(sent ? Color.accentColor : .secondary)
                .opacity(sent || hovering || isSelected || model.sending.contains(tab.url) ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.14) : hovering ? Color.primary.opacity(0.04) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .opacity(closing ? 0.6 : 1)
        .onHover { hovering = $0 }
    }

    /// What Sift saved of this link, as one small symbol.
    private var savedSymbol: (symbol: String, help: String)? {
        guard let e = model.library[tab.url] else { return nil }
        if e.transcript == true { return ("captions.bubble", "Transcript saved") }
        if e.status == "ok", e.words > 0 { return ("doc.text", "Text saved: \(e.words) words") }
        return nil
    }

    /// X posts carry their text in the title; the meta line shows the author.
    private func xText(_ p: Preview?) -> String? {
        guard p?.site == "x.com", let t = p?.title, !t.isEmpty else { return nil }
        return t
    }

    static func dateFormat(_ d: Date) -> Date.FormatStyle {
        // The year shows when it is not this year.
        Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
            ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
    }

    /// Page image, author avatar, or the site's icon.
    @ViewBuilder
    private func thumbnail(_ p: Preview?) -> some View {
        let source = p?.imageURL ?? p?.avatarURL ?? "https://\(tab.host)/favicon.ico"
        AsyncImage(url: URL(string: source)) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.primary.opacity(0.05)
                    Image(systemName: tab.sourceSymbol).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: Card

    private func card(_ a: Assignment?, _ preview: Preview?, _ closing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(preview)
            VStack(alignment: .leading, spacing: 8) {
                // Source line: where it is from and when, one quiet line.
                HStack(spacing: 5) {
                    if model.isAll { Image(systemName: tab.sourceSymbol).help("From \(tab.source)") }
                    Text(tab.host).lineLimit(1).truncationMode(.middle)
                    if let d = tab.lastViewed {
                        Text("·")
                        // The year shows when it is not this year.
                        Text(d, format: Self.dateFormat(d)).fixedSize()
                    }
                    Spacer(minLength: 0)
                    if a?.manual == true { Image(systemName: "hand.point.up.left").help("Sorted by hand") }
                    if closing { Image(systemName: "xmark.square").help("Closes on iPhone") }
                }
                .font(.caption).foregroundStyle(.secondary)

                Text(cardTitle(preview))
                    .font(.system(.headline, design: .default).weight(.semibold))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(closing, color: .secondary)

                if let text = bodyText(preview) {
                    Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if preview == nil {
                    Text("Loading preview…").font(.callout).foregroundStyle(.tertiary)
                }
                if let note = model.note(for: tab.url) {
                    Label(note, systemImage: "pencil.line").font(.callout).lineLimit(3)
                }
                if let out = preview?.outboundURL, let url = URL(string: out) {
                    Button { TabActions.openInSafari(out) } label: {
                        Label((url.host() ?? out).replacingOccurrences(of: "www.", with: "") + url.path(), systemImage: "arrow.up.right")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help(out)
                }
                Spacer(minLength: 0)
                // Footer: send left, theme right (only where the theme is
                // not already the page you are on).
                if a != nil {
                    HStack(spacing: 8) {
                        SendButton(tab: tab)
                            .menuStyle(.button)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .fixedSize()
                        Spacer(minLength: 0)
                        if showTheme {
                            Menu { moveMenu } label: { Text(a.map { Project.displayName($0.project) } ?? "Move to…").lineLimit(1) }
                                .menuStyle(.button)
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 150, alignment: .trailing)
                                .help("Theme: \(a?.project ?? "")")
                        }
                    }
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .opacity(closing ? 0.6 : 1)
    }

    /// Page image when there is one. X posts get a band with the author's
    /// avatar (or initial when oEmbed gave no avatar), then the post image.
    @ViewBuilder
    private func header(_ p: Preview?) -> some View {
        if p?.site == "x.com" {
            VStack(alignment: .leading, spacing: 0) {
                if let s = p?.imageURL, let url = URL(string: s) { headerImage(url) }
                HStack(spacing: 8) {
                    initialCircle(p).overlay {
                        if let s = p?.avatarURL, let url = URL(string: s) {
                            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                                .clipShape(Circle())
                        }
                    }
                    Text(p?.title ?? "").font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text("𝕏").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.top, 12)
            }
        } else if let s = p?.imageURL, let url = URL(string: s) {
            headerImage(url)
        }
    }

    private func initialCircle(_ p: Preview?) -> some View {
        Text(String((p?.title ?? "X").prefix(1)).uppercased())
            .font(.callout.weight(.semibold))
            .frame(width: 26, height: 26)
            .background(Circle().fill(.quaternary))
    }

    private func headerImage(_ url: URL) -> some View {
        Color.clear
            .frame(height: 150)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        // Loading or failed: a quiet panel, not a grey block.
                        ZStack {
                            Color.primary.opacity(0.035)
                            Text(tab.host).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .clipped()
    }

    private func cardTitle(_ p: Preview?) -> String { Self.title(tab, p) }

    static func title(_ tab: SafariTab, _ p: Preview?) -> String {
        if p?.site == "x.com", let text = p?.text, !text.isEmpty, !p!.failed {
            // The post itself is the title; the header carries the author.
            return text
        }
        if tab.hasUsefulTitle { return tab.title.replacingOccurrences(of: #" / X$"#, with: "", options: .regularExpression) }
        if let p, !p.failed, !p.title.isEmpty { return p.title }
        return tab.url
    }

    private func bodyText(_ p: Preview?) -> String? {
        guard let p, !p.failed, !p.text.isEmpty, p.site != "x.com" else {
            if p?.failed == true { return "No preview. The page needs a login, was deleted, or blocks fetching." }
            return nil
        }
        return p.text
    }

    @ViewBuilder
    private var moveMenu: some View {
        ForEach(model.projects) { p in
            Button(p.name) { model.move(tab, to: p.name) }
        }
        Divider()
        ForEach(Project.buckets, id: \.self) { b in
            Button(Project.displayName(b)) { model.move(tab, to: b) }
        }
    }

}

enum TabActions {
    /// Adds the link to Safari's Reading List through Safari's own scripting
    /// command. macOS asks the user once to allow Sift to control Safari.
    /// Returns an error message, or nil on success.
    @MainActor
    static func addToReadingList(_ url: String, title: String, preview: String) -> String? {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ") + "\""
        }
        var source = "tell application \"Safari\" to add reading list item \(quoted(url))"
        if !title.isEmpty { source += " with title \(quoted(String(title.prefix(200))))" }
        if !preview.isEmpty { source += " and preview text \(quoted(String(preview.prefix(400))))" }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        return code == -1743 ? "Allow Sift to control Safari in System Settings > Privacy & Security > Automation." : (error[NSAppleScript.errorMessage] as? String ?? "Safari did not add the link.")
    }

    @MainActor
    static func openInSafari(_ string: String) {
        guard let url = URL(string: string) else { return }
        let safari = URL(filePath: "/Applications/Safari.app")
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The inspector: everything Sift knows about one tab.
struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    let tab: SafariTab

    var body: some View {
        let p = model.previews[tab.url]
        let a = model.assignment(for: tab)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = p?.imageURL, let url = URL(string: s) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle().fill(.quaternary).aspectRatio(1.91, contentMode: .fit)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(p?.site.isEmpty == false ? p!.site : tab.host).font(.caption).foregroundStyle(.secondary)
                Text(headline(p)).font(.title3.weight(.semibold)).textSelection(.enabled)
                if let text = p?.text, !text.isEmpty {
                    Text(text).textSelection(.enabled)
                } else if p == nil {
                    HStack { ProgressView().controlSize(.small); Text("Fetching preview…").foregroundStyle(.secondary) }
                } else if p?.failed == true {
                    Text("No preview. The page needs a login, was deleted, or blocks fetching.").foregroundStyle(.secondary)
                }
                if let a {
                    Divider()
                    LabeledContent("Project", value: a.project)
                }
                Divider()
                Text(tab.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(4)
                HStack {
                    Button("Open in Safari") { TabActions.openInSafari(tab.url) }
                    Button(model.isQueuedToClose(tab) ? "Keep Open" : "Close on iPhone") { model.toggleClose(tab) }
                    Spacer()
                    Button { Task { await model.fetchPreviews(for: [tab], force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Fetch the preview again")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: tab.url) { await model.preview(for: tab) }
    }

    private func headline(_ p: Preview?) -> String {
        if let p, !p.failed, !p.title.isEmpty, !(tab.hasUsefulTitle && p.site == "x.com") { return p.title }
        return tab.displayTitle
    }
}

/// How to build the iPhone Shortcut that closes the listed tabs.
struct ShortcutGuide: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSteps = false

    /// The ready-made "Sift: Close Tabs" shortcut, shared from iCloud.
    static let installURL = URL(string: "https://www.icloud.com/shortcuts/6afe4511e1064e4297e749b5b7e55290")!

    // The layout that works on iOS 26 (tested 2026-11-14): look each tab up
    // right before closing it, and switch to it first; closing a tab object
    // carried through a loop failed with "something went wrong".
    private let steps = [
        "Open Shortcuts on the iPhone and create a new shortcut named \"Sift: Close Tabs\".",
        "Add \"Get File\". Turn off \"Show Document Picker\" and set the path to Sift/close.txt in iCloud Drive.",
        "Add \"Get Text from Input\" so the file becomes text.",
        "Add \"Split Text\" by New Lines: one address per item.",
        "Add \"Repeat with Each\" on the split text.",
        "Inside the repeat, add \"Find Tab\", then Add Filter: URL is Repeat Item.",
        "Inside the repeat, add \"Switch to Tab\" with the Tab that Find Tab found.",
        "Inside the repeat, add \"Close Tab\" with that same Tab.",
        "Test with one throwaway tab first. Then click Reload in Sift: closed tabs leave the list.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Close tabs on the iPhone").font(.title2.weight(.semibold))
            Text("A Mac cannot close tabs on another device, so Sift writes the close list to iCloud Drive and a Shortcut on the iPhone closes them. Install the Shortcut once.")
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 18) {
                if let qr = QRCode.image(for: Self.installURL.absoluteString) {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 150, height: 150)
                        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("QR code for the Sift: Close Tabs shortcut")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan with the iPhone camera").font(.headline)
                    Text("It opens Shortcuts and adds \"Sift: Close Tabs\". Run it whenever you want the marked tabs closed, or from Siri or the Share sheet.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Open Link") { NSWorkspace.shared.open(Self.installURL) }
                        Button("Copy Link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.installURL.absoluteString, forType: .string)
                        }
                    }
                }
            }
            DisclosureGroup("Or build it yourself", isExpanded: $showSteps) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 18, alignment: .trailing)
                            Text(step)
                        }
                    }
                }
                .padding(.top, 6)
            }
            Text("Safari's Shortcut actions need iOS 17 or later. Action names can differ slightly between iOS versions.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show close.txt in Finder") {
                    CloseList.ensureExists()
                    NSWorkspace.shared.activateFileViewerSelecting([CloseList.fileURL])
                }
                .disabled(!CloseList.iCloudDriveAvailable)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

/// The browser pane slides over the content instead of pushing it aside.
enum BrowserOverlay {
    static func width(for available: CGFloat) -> CGFloat {
        min(max(available * 0.46, 420), max(available - 280, 320))
    }
}

/// A QR code from Core Image, no dependencies.
enum QRCode {
    static func image(for text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
