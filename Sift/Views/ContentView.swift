import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case unsorted
    case closeQueue
    case archive
    case duplicates
    case broken
    /// Videos and reels with a transcript.
    case transcripts
    /// A saved full-text search.
    case saved(String)
    /// The overview, showing one source (see AppModel.selectDevice).
    case source(String)
    case site(String)
    /// Links sent to one destination.
    case destination(String)
    case project(String)
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .overview
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            Group {
                let item = selection ?? .overview
                if !model.hasReadableSource {
                    NoSourcesView()
                } else if showsGraph(item) {
                    GraphView(selection: $selection)
                } else {
                    TabList(item: item).id(item)
                }
            }
            .onChange(of: selection) { _, new in
                if let new, !showsGraph(new) { model.graphTheme = nil }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SafariAccessBanner()
                    UnsortedBanner()
                }
            }
        }
        .toolbar { toolbar }
        // First run, or steps added since the user last saw the guide.
        .task {
            guard model.onboarding == nil, let pending = model.pendingOnboarding() else { return }
            model.onboarding = pending
            openWindow(id: Onboarding.windowID)
        }
        // Demo mode: window size, appearance and first view from the launch
        // arguments (see Demo.swift and scripts/screenshots.sh).
        .task {
            guard Demo.isOn else { return }
            Demo.applyAppearance()
            try? await Task.sleep(for: .milliseconds(300))
            Demo.sizeMainWindow()
            switch Demo.startView {
            case .theme(let name):
                model.graphTheme = name
                selection = .project(name)
            case .list(let id):
                selection = .source(id)
            case .settings:
                openSettings()
            case .graph, nil:
                break
            }
        }
        // Coming back from System Settings: check Full Disk Access again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.loadError != nil, !model.onboardingOpen { model.reload() }
        }
        // While the Setup Guide is open, it shows the review itself.
        .sheet(isPresented: .init(get: { model.themeProposal != nil && !model.onboardingOpen }, set: { if !$0 { model.themeProposal = nil } })) {
            ThemeReview().environment(model)
        }
        .alert("Sift", isPresented: .init(get: { model.exportMessage != nil }, set: { if !$0 { model.exportMessage = nil } })) {
            Button("OK") { model.exportMessage = nil }
        } message: {
            Text(model.exportMessage ?? "")
        }
        .alert("Your Sift data", isPresented: .init(get: { model.dataProblem != nil }, set: { if !$0 { model.dataProblem = nil } })) {
            Button("Show Files") {
                NSWorkspace.shared.activateFileViewerSelecting([StateFile.url])
                model.dataProblem = nil
            }
            Button("OK") { model.dataProblem = nil }
        } message: {
            Text(model.dataProblem ?? "")
        }
        .alert("Not sent", isPresented: .init(get: { model.sendError != nil }, set: { if !$0 { model.sendError = nil } })) {
            Button("OK") { model.sendError = nil }
        } message: {
            Text(model.sendError ?? "")
        }
        .alert(model.sortError == ClaudeCodeRunner.loginMessage ? "Sign in to Claude Code" : "Sorting stopped",
               isPresented: .init(get: { model.sortError != nil }, set: { if !$0 { model.sortError = nil } })) {
            if model.sortError == ClaudeCodeRunner.loginMessage {
                Button("Open Terminal") {
                    model.sortError = nil
                    NSWorkspace.shared.open(URL(filePath: "/System/Applications/Utilities/Terminal.app"))
                }
                Button("Cancel", role: .cancel) { model.sortError = nil }
            } else {
                Button("OK") { model.sortError = nil }
            }
        } message: {
            Text(model.sortError ?? "")
        }
    }

    /// The overview, a source, or the theme the graph is zoomed into.
    private func showsGraph(_ item: SidebarItem) -> Bool {
        switch item {
        case .overview: true
        case .project(let p): p == model.graphTheme
        default: false
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Source", selection: .init(get: { model.state.deviceID ?? "" }, set: { model.selectDevice($0) })) {
                Text("All Sources (\(model.allSourcesCount))").tag(AppModel.allSourcesID)
                Divider()
                ForEach(model.devices) { d in Text("\(d.name) (\(d.tabCount))").tag(d.id) }
                ForEach(model.chromeProfiles) { p in
                    Text("\(p.browser)\(model.chromeProfileName(p).map { ", \($0)" } ?? "") (\(p.tabs.count))").tag(p.id)
                }
                if model.readingListCount > 0 || model.instagramCount > 0 { Divider() }
                if model.readingListCount > 0 {
                    Text("Reading List (\(model.readingListCount))").tag(ReadingListReader.sourceID)
                }
                if model.xConnected {
                    Text("X Bookmarks (\(model.xBookmarkIDs.count))").tag(AppModel.xBookmarksSourceID)
                }
                if model.state.instagramExportPath != nil, model.instagramCount > 0 {
                    Text("Instagram Saved (\(model.instagramCount))").tag(InstagramReader.sourceID)
                }
                ForEach(model.state.importedSources) { source in
                    Text("\(source.name) (\(model.importCounts[source.id] ?? 0))").tag(LinkImporter.sourcePrefix + source.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.hasReadableSource)
        }
        // Toolbar items keep one size: their content must not change while
        // Claude works (AppKit aborts when toolbar layout changes every
        // frame). Progress shows in the banner instead.
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.discoverThemes() }
            } label: {
                Label("Discover Themes", systemImage: "circle.hexagongrid.circle")
            }
            .help("Ask Claude to find the themes in all your links. You review them before anything changes.")
            .disabled(model.isSorting || model.isDiscovering)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.sortUnsorted() }
            } label: {
                Label("Sort with Claude", systemImage: "sparkles")
            }
            .help(model.themes.isEmpty ? "Discover your themes first." : "Sort the links that are in no theme yet into your themes.")
            .disabled(model.unsortedCount == 0 || model.themes.isEmpty || model.isSorting || model.isDiscovering)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(Exporters.all, id: \.id) { exporter in
                    Button(exporter.name) { model.runExport(exporter) }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export your themes and links: Obsidian, Markdown, CSV or JSON.")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
        }
        // Shows once a newer release exists (UpdateChecker, daily).
        if let version = UpdateChecker.shared.available {
            ToolbarItem(placement: .primaryAction) {
                Button { UpdateChecker.shared.install() } label: {
                    Label("Update to \(version)", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                }
                .help("Download Sift \(version), check it, then quit and open the new version.")
            }
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    // Each section folds; the choice is remembered.
    @AppStorage("sidebar.themes") private var showThemes = true
    @AppStorage("sidebar.actions") private var showActions = true
    @AppStorage("sidebar.sites") private var showSites = true
    @AppStorage("sidebar.outside") private var showOutside = true

    var body: some View {
        List(selection: $selection) {
            Label { HStack { Text("Overview"); Spacer(); count(model.allSourcesCount) } } icon: { Image(systemName: "circle.hexagongrid") }
                .tag(SidebarItem.overview)
            // The sources behind the overview, with counts. Click one to show
            // only that source; All Sources shows everything.
            ForEach(sourceRows, id: \.id) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.symbol).frame(width: 16).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(row.name)
                        if let detail = row.detail { Text(detail).foregroundStyle(.tertiary) }
                    }
                    .lineLimit(1)
                    Spacer()
                    count(row.count)
                }
                .font(.callout)
                .padding(.leading, 18)
                .tag(SidebarItem.source(row.id))
            }
            Label { HStack { Text("Unsorted"); Spacer(); count(model.unsortedCount) } } icon: { Image(systemName: "tray") }
                .tag(SidebarItem.unsorted)
            Label { HStack { Text("Archive"); Spacer(); count(model.archivedTabs.count) } } icon: { Image(systemName: "archivebox") }
                .tag(SidebarItem.archive)
                .help("Links that left their source. Sift keeps their theme, use and action.")
            let dupes = model.duplicateTabs.count
            if dupes > 0 {
                Label { HStack { Text("Duplicates"); Spacer(); count(dupes) } } icon: { Image(systemName: "square.on.square") }
                    .tag(SidebarItem.duplicates)
                    .help("The same page saved more than once, from different sources or with tracking parameters.")
            }
            let transcripts = model.transcriptTabs.count
            if transcripts > 0 {
                Label { HStack { Text("Transcripts"); Spacer(); count(transcripts) } } icon: { Image(systemName: "captions.bubble") }
                    .tag(SidebarItem.transcripts)
                    .help("Videos and reels whose words Sift saved. Select one to read its transcript.")
            }
            let broken = model.brokenTabs.count
            if broken > 0 {
                Label { HStack { Text("Broken Links"); Spacer(); count(broken) } } icon: { Image(systemName: "link.badge.plus") }
                    .tag(SidebarItem.broken)
                    .help("Pages that are gone: not found, or the site no longer exists. Sift keeps what it saved.")
            }
            if !model.isSavedList {
                Label { HStack { Text("To Close"); Spacer(); count(model.state.closeQueue.count) } } icon: { Image(systemName: "xmark.square") }
                    .tag(SidebarItem.closeQueue)
            }

            if !model.state.savedSearches.isEmpty {
                Section("Saved searches") {
                    ForEach(model.state.savedSearches, id: \.self) { q in
                        Label(q, systemImage: "magnifyingglass")
                            .tag(SidebarItem.saved(q))
                            .contextMenu { Button("Remove Saved Search", role: .destructive) { model.removeSavedSearch(q) } }
                    }
                }
            }
            Section("Themes", isExpanded: $showThemes) {
                ForEach(model.activeProjects, id: \.project) { item in
                    HStack { Text(item.project); Spacer(); count(item.count) }
                        .tag(SidebarItem.project(item.project))
                }
            }
            Section("Sent to", isExpanded: $showActions) {
                ForEach(model.destinations) { d in
                    Label { HStack { Text(d.name).lineLimit(1); Spacer(); count(model.sentTabs(to: d.id).count) } } icon: { d.image }
                        .help(d.detail.isEmpty ? d.name : "\(d.name) · \(d.detail)")
                        .tag(SidebarItem.destination(d.id))
                }
                if model.destinations.isEmpty {
                    SettingsLink { Label("Add a Destination…", systemImage: "plus") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Sites", isExpanded: $showSites) {
                ForEach(model.sites, id: \.host) { site in
                    HStack { Text(site.host).lineLimit(1); Spacer(); count(site.count) }
                        .tag(SidebarItem.site(site.host))
                }
            }
            Section("Outside your themes", isExpanded: $showOutside) {
                ForEach(Project.buckets, id: \.self) { bucket in
                    HStack { Text(Project.displayName(bucket)); Spacer(); count(model.count(bucket)) }
                        .tag(SidebarItem.project(bucket))
                }
            }
        }
        .listStyle(.sidebar)
        // A source row switches the source; the canvas then shows only it.
        .onChange(of: selection) { _, new in
            if case .source(let id) = new, model.state.deviceID != id { model.selectDevice(id) }
            if new == .overview, !model.isAll { model.selectDevice(AppModel.allSourcesID) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { LibraryStatus() }
    }

    private struct SourceRow {
        let id: String; let name: String; let symbol: String; let count: Int
        /// Quieter text after the name: the device of a Safari source.
        var detail: String? = nil
    }

    private var sourceRows: [SourceRow] {
        // Overview itself is All Sources; these rows narrow it to one source.
        var rows: [SourceRow] = []
        for d in model.devices where d.tabCount > 0 {
            rows.append(.init(id: d.id, name: "Safari", symbol: "safari", count: d.tabCount, detail: d.name))
        }
        for p in model.chromeProfiles {
            // A profile that has not reported for a day says so.
            let name = model.chromeProfileName(p)
            let detail = p.isStale ? [name, "last seen \(p.updated.formatted(.relative(presentation: .named)))"].compactMap { $0 }.joined(separator: ", ") : name
            rows.append(.init(id: p.id, name: p.browser, symbol: "globe", count: p.tabs.count, detail: detail))
        }
        if model.readingListCount > 0 { rows.append(.init(id: ReadingListReader.sourceID, name: "Reading List", symbol: "eyeglasses", count: model.readingListCount)) }
        if model.instagramCount > 0 { rows.append(.init(id: InstagramReader.sourceID, name: "Instagram Saved", symbol: "camera", count: model.instagramCount)) }
        if model.xConnected { rows.append(.init(id: AppModel.xBookmarksSourceID, name: "X Bookmarks", symbol: "bookmark", count: model.xBookmarkIDs.count)) }
        for i in model.state.importedSources {
            rows.append(.init(id: LinkImporter.sourcePrefix + i.id, name: i.name, symbol: "tray.and.arrow.down", count: model.importCounts[i.id] ?? 0))
        }
        return rows
    }

    private func count(_ n: Int) -> some View {
        Text("\(n)").foregroundStyle(.secondary).monospacedDigit()
    }
}

/// The detail pane when no source has links yet.
private struct NoSourcesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentUnavailableView {
            Label("No links yet", systemImage: "tray")
        } description: {
            Text("Add a source, like your Safari tabs or an export from a read-later app, and your links show up here.")
        } actions: {
            Button("Open Setup Guide") {
                model.startSetupGuide()
                model.onboardingGo(to: "sources")
                openWindow(id: Onboarding.windowID)
            }
            .buttonStyle(.borderedProminent)
            Button("Import Links File…") { model.importLinksFile() }
        }
    }
}

/// Safari's files cannot be read. Not modal: the other sources keep
/// working. Full Disk Access is set up in the Setup Guide's Sources step.
private struct SafariAccessBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("banner.safariAccess.hidden") private var hidden = false

    var body: some View {
        if let error = model.loadError, !hidden {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield").foregroundStyle(.orange)
                Text(model.needsDiskAccess
                     ? "Sift cannot read your Safari tabs or Reading List without Full Disk Access."
                     : error.localizedDescription)
                    .lineLimit(2)
                Spacer()
                if model.needsDiskAccess {
                    Button("Set Up…") {
                        model.startSetupGuide()
                        model.onboardingGo(to: "sources")
                        openWindow(id: Onboarding.windowID)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Check Again") { model.reload() }
                Button { hidden = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Hide this. Settings > Inputs still shows Safari's status.")
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// Says when the current source has links that are in no theme yet (for
/// example right after adding Instagram or the Reading List), and offers the
/// two ways to sort them.
private struct UnsortedBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = model.unsortedCount
        if count > 0 || model.isSorting || model.isDiscovering {
            HStack(spacing: 10) {
                if model.isSorting {
                    ProgressView().controlSize(.small)
                    Text("\(model.sortingOnDevice ? "Sorting on this Mac" : "Sorting with Claude"): \(model.sortProgress.done) of \(model.sortProgress.total)")
                } else if model.isDiscovering {
                    ProgressView().controlSize(.small)
                    Text("Claude is reading all your links to find themes…")
                } else {
                    Image(systemName: "circle.dotted").foregroundStyle(.tint)
                    if model.themes.isEmpty {
                        Text("\(count) links, no themes yet. Claude reads them and proposes the themes you keep coming back to.")
                        Spacer()
                        Button("Setup Guide") {
                            model.startSetupGuide()
                            model.onboardingGo(to: "themes")
                            openWindow(id: Onboarding.windowID)
                        }
                        Button("Discover Themes") { Task { await model.discoverThemes() } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("\(count) link\(count == 1 ? " is" : "s are") not in a theme yet. They are under Unsorted, not on the graph.")
                        Spacer()
                        Button("Discover Themes Again") { Task { await model.discoverThemes() } }
                            .help("Rare: Claude reads every source together and may propose new themes. You review them first.")
                        Button("Sort into Themes") { Task { await model.sortUnsorted() } }
                            .buttonStyle(.borderedProminent)
                            .help("Puts each link into one of the themes you have.")
                    }
                }
                if model.isSorting || model.isDiscovering { Spacer() }
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// The library's state at the foot of the sidebar: how many links have their
/// text saved, and a progress bar while capture runs in the background.
private struct LibraryStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = model.archive.count
        let saved = model.capturedCount
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical").foregroundStyle(.secondary)
                Text("Library").font(.caption.weight(.semibold))
                DemoBadge()
                Spacer()
                Text("\(saved) of \(total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if model.isTranscribing {
                ProgressView(value: Double(model.transcriptProgress.done), total: Double(max(model.transcriptProgress.total, 1)))
                    .progressViewStyle(.linear).controlSize(.small)
                Text("YouTube transcripts: \(model.transcriptProgress.done) of \(model.transcriptProgress.total)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if model.isTranscribingReels {
                ProgressView(value: Double(model.reelProgress.done), total: Double(max(model.reelProgress.total, 1)))
                    .progressViewStyle(.linear).controlSize(.small)
                Text("Reel transcripts: \(model.reelProgress.done) of \(model.reelProgress.total)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if model.isFetchingInstagramImages {
                ProgressView(value: Double(model.instagramImageProgress.done), total: Double(max(model.instagramImageProgress.total, 1)))
                    .progressViewStyle(.linear).controlSize(.small)
                Text("Instagram images: \(model.instagramImageProgress.done) of \(model.instagramImageProgress.total)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if model.isCapturing {
                ProgressView(value: Double(model.captureProgress.done), total: Double(max(model.captureProgress.total, 1)))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                Text("Saving page text: \(model.captureProgress.done) of \(model.captureProgress.total)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .help("Sift saves the readable text of your links on this Mac, so it stays when a tab closes.")
    }
}
