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
    /// This list's token for the keyboard shortcuts (KeyRouter).
    @State private var keyOwner = UUID()
    /// Only unseen links, like an unread filter in mail.
    @AppStorage("list.unseenOnly") private var unseenOnly = false
    /// A saved search's links, loaded from the search index.
    @State private var savedHits: [SafariTab] = []
    /// Full-text matches for the filter: url to snippet, from the search index.
    @State private var textHits: [String: String] = [:]

    private var project: String? {
        if case .project(let p) = item { return p }
        return nil
    }

    private var title: String {
        switch item {
        case .today: "Today"
        case .feed, .feedFolder: "Feeds"
        case .overview: "Overview"
        case .source(let id): model.sourceTitle(id)
        case .unsorted: "Unsorted"
        case .closeQueue: "To Close"
        case .archive: "Archive"
        case .duplicates: "Duplicates"
        case .broken: "Broken Links"
        case .transcripts: "Transcripts"
        case .saved(let q): "“\(q)”"
        case .project(let p): Project.displayName(p)
        case .site(let host): host
        case .destination(let id): model.destination(id)?.name ?? "Destination"
        }
    }

    private var all: [SafariTab] {
        switch item {
        case .today, .feed, .feedFolder: []
        case .overview, .source: model.tabs
        case .unsorted: model.tabs(in: nil)
        case .closeQueue: model.closeQueueTabs
        case .archive: model.archivedTabs
        case .duplicates: model.duplicateTabs
        case .broken: model.brokenTabs
        case .transcripts: model.transcriptTabs
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
        var base = siteFilter.map { host in all.filter { $0.host == host } } ?? all
        if unseenOnly { base = base.filter { !model.isSeen($0.url) } }
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
                LazyVStack(spacing: 2) {
                    ForEach(rows) { tab in
                        cell(tab).id(tab.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                // Rows stay clear of the browser pane, so none hides under it.
                .padding(.trailing, showInspector ? BrowserOverlay.width(for: listWidth) : 0)
            }
            .background(Color(nsColor: .textBackgroundColor))
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
        // The page sits beside the list; the list gets narrower, nothing
        // covers it.
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if showInspector, let tab = rows.first(where: { $0.id == selected }) {
                WebPane(tab: tab) { withAnimation(.snappy) { showInspector = false } }
                    .containerRelativeFrame(.horizontal) { width, _ in BrowserOverlay.width(for: width) }
                    .background(.background)
                    .overlay(alignment: .leading) { Divider() }
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar { listToolbar }
        .onAppear { KeyRouter.shared.register(keyOwner, handleKey) }
        .onDisappear { KeyRouter.shared.unregister(keyOwner) }
        .sheet(isPresented: $showShortcutGuide) { ShortcutGuide() }
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem {
            Button { model.saveSearch(search) } label: { Label("Save Search", systemImage: "bookmark") }
                .disabled(search.count < 2 || model.state.savedSearches.contains(search))
                .help("Keep this search in the sidebar.")
        }
        ToolbarItemGroup {
            Toggle(isOn: $unseenOnly) { Label("Unseen Only", systemImage: "circle.inset.filled") }
                .help("Show only links nobody has opened or marked as seen, on any device.")
            Menu {
                Button("Mark All as Seen") { model.setSeen(rows.map(\.url), true) }
                Button("Mark All as Unseen") { model.setSeen(rows.map(\.url), false) }
            } label: { Label("Seen", systemImage: "eye") }
            .help("Mark every link in this list as seen or unseen.")
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
                    Label(model.isChrome ? "Close All in Chrome" : "Close All on iPhone", systemImage: "xmark.square")
                }
                .help(model.isChrome ? "Close every tab in this list in Chrome." : "Add every tab in this list to the close list for the iPhone Shortcut.")
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
            VStack(alignment: .leading, spacing: 2) {
                if CloseList.iCloudDriveAvailable {
                    Text("\(model.iPhoneCloseQueue.count) tabs wait in iCloud Drive/Sift/close.txt. Run the Sift Shortcut on the iPhone to close them.")
                } else {
                    Text("iCloud Drive is off on this Mac, so the iPhone cannot read the close list.")
                }
                if model.chromeCloseCount > 0 {
                    Text("Chrome closes \(model.chromeCloseCount) of them within a minute while it is open.")
                        .foregroundStyle(.secondary)
                }
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
        TabCard(tab: tab, isSelected: selected == tab.id, showTheme: project == nil || Project.buckets.contains(project ?? ""))
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

    /// Google Reader keys for saved links (KeyMap.swift).
    private func handleKey(_ action: KeyAction) -> Bool {
        let tab = rows.first { $0.id == selected }
        switch action {
        case .next: step(1)
        case .previous: step(-1)
        case .open:
            if selected == nil { step(1) }
            withAnimation(.snappy) { showInspector.toggle() }
        case .original:
            guard let tab else { return false }
            model.openInApp(tab.url)
        case .toggleSeen:
            guard let tab else { return false }
            model.setSeen([tab.url], !model.isSeen(tab.url))
        case .markAllSeen:
            model.setSeen(rows.map(\.url), true)
            model.note("Marked \(rows.count) as seen")
        case .copyLink:
            guard let tab else { return false }
            model.copy(tab.url)
            model.note("Link copied")
        case .follow:
            guard let tab, let input = AppModel.followInput(forLink: tab.url) else { return false }
            model.followQuick(input)
        case .send:
            guard let tab else { return false }
            guard let d = model.defaultDestination(for: tab) else {
                model.note("This theme has no destination. Choose one in the theme header.")
                return true
            }
            Task { await model.send(tab, to: d) }
            model.note("Sent to \(d.name)")
        default:
            return false
        }
        return true
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

/// One link as a row: thumbnail, title, meta line, theme, send.
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
            row(a, preview, closing)
        }
        .contentShape(Rectangle())
        .task(id: tab.url) { await model.preview(for: tab) }
        .contextMenu {
            Button(model.isSeen(tab.url) ? "Mark as Unseen" : "Mark as Seen") {
                model.setSeen([tab.url], !model.isSeen(tab.url))
            }
            Divider()
            Button("Open in Safari") { TabActions.openInSafari(tab.url) }
            Button("Add to Reading List") {
                model.exportMessage = TabActions.addToReadingList(tab.url, title: cardTitle(preview), preview: bodyText(preview) ?? "")
            }
            Button("Copy Link") { model.copy(tab.url) }
            if let label = AppModel.followLabel(forLink: tab.url), let input = AppModel.followInput(forLink: tab.url) {
                Button("Follow \(label)") { model.followQuick(input) }
            }
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
                Button(model.closeLabel(tab)) { model.toggleClose(tab) }
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
                // Unseen reads like unread mail: a dot and a heavier title.
                let seen = model.isSeen(tab.url)
                HStack(spacing: 6) {
                    if !seen { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                    Text(cardTitle(preview))
                        .font(.body.weight(seen ? .regular : .semibold))
                        .foregroundStyle(seen ? .secondary : .primary)
                        .lineLimit(1)
                }
                    .strikethrough(closing, color: .secondary)
                HStack(spacing: 5) {
                    Image(systemName: tab.sourceSymbol).help("From \(tab.source)")
                    Text(tab.host).lineLimit(1).fixedSize()
                    if let d = tab.lastViewed {
                        Text("·")
                        Text(d, format: Self.dateFormat(d)).fixedSize()
                    }
                    if let seconds = model.library[tab.url]?.duration {
                        Text("·")
                        Text(Self.length(seconds)).monospacedDigit().fixedSize()
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
            if closing { Image(systemName: "xmark.square").foregroundStyle(.secondary).help(model.closesInChrome(tab) ? "Closes in Chrome" : "Closes on iPhone") }
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

    /// 6055 seconds as "1:40:55", 754 as "12:34".
    static func length(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func dateFormat(_ d: Date) -> Date.FormatStyle {
        // The year shows when it is not this year.
        Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
            ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
    }

    /// Page image, author avatar, or the site's icon.
    @ViewBuilder
    private func thumbnail(_ p: Preview?) -> some View {
        // Demo mode has no network, so no site icon.
        let source = p?.imageURL ?? p?.avatarURL ?? (Demo.isOn ? "" : "https://\(tab.host)/favicon.ico")
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
        if Demo.isOn { return Demo.offMessage }
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
                    Button(model.closeLabel(tab)) { model.toggleClose(tab) }
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
