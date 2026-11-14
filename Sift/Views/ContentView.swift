import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case unsorted
    case closeQueue
    case archive
    case site(String)
    case action(NextAction)
    case project(String)
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        Group {
            if let error = model.loadError {
                AccessView(error: error)
            } else {
                NavigationSplitView {
                    Sidebar(selection: $selection)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                } detail: {
                    Group {
                        switch selection ?? .overview {
                        case .overview: GraphView(selection: $selection)
                        case let other: TabList(item: other).id(other)
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) { UnsortedBanner() }
                }
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: .init(get: { model.themeProposal != nil }, set: { if !$0 { model.themeProposal = nil } })) {
            ThemeReview().environment(model)
        }
        .alert("Sift", isPresented: .init(get: { model.exportMessage != nil }, set: { if !$0 { model.exportMessage = nil } })) {
            Button("OK") { model.exportMessage = nil }
        } message: {
            Text(model.exportMessage ?? "")
        }
        .alert("Sorting stopped", isPresented: .init(get: { model.sortError != nil }, set: { if !$0 { model.sortError = nil } })) {
            Button("OK") { model.sortError = nil }
        } message: {
            Text(model.sortError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Source", selection: .init(get: { model.state.deviceID ?? "" }, set: { model.selectDevice($0) })) {
                Text("All Sources (\(model.allSourcesCount))").tag(AppModel.allSourcesID)
                Divider()
                ForEach(model.devices) { d in Text("\(d.name) (\(d.tabCount))").tag(d.id) }
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
            .disabled(model.devices.isEmpty)
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
            Button {
                Task { await model.suggestActions() }
            } label: {
                Label("Suggest Next Actions", systemImage: "arrow.forward.circle")
            }
            .help("Ask Claude what to do next with sorted links that have no next action.")
            .disabled(model.tabsWithoutAction.isEmpty || model.isSorting || model.isDiscovering)
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
            Label { HStack { Text("Overview"); Spacer(); count(model.tabs.count) } } icon: { Image(systemName: "circle.hexagongrid") }
                .tag(SidebarItem.overview)
            // The sources behind the overview, with counts. Click one to show
            // only that source; All Sources shows everything.
            ForEach(sourceRows, id: \.id) { row in
                Button {
                    model.selectDevice(row.id)
                    selection = .overview
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: row.symbol).frame(width: 16).foregroundStyle(.secondary)
                        Text(row.name).lineLimit(1)
                        Spacer()
                        count(row.count)
                    }
                    .font(.callout)
                    .padding(.leading, 18)
                    .foregroundStyle(model.state.deviceID == row.id ? Color.accentColor : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Label { HStack { Text("Unsorted"); Spacer(); count(model.unsortedCount) } } icon: { Image(systemName: "tray") }
                .tag(SidebarItem.unsorted)
            Label { HStack { Text("Archive"); Spacer(); count(model.archivedTabs.count) } } icon: { Image(systemName: "archivebox") }
                .tag(SidebarItem.archive)
                .help("Links that left their source. Sift keeps their theme, use and action.")
            if !model.isSavedList {
                Label { HStack { Text("To close on iPhone"); Spacer(); count(model.state.closeQueue.count) } } icon: { Image(systemName: "xmark.square") }
                    .tag(SidebarItem.closeQueue)
            }

            Section("Themes", isExpanded: $showThemes) {
                ForEach(model.activeProjects, id: \.project) { item in
                    HStack { Text(item.project); Spacer(); count(item.count) }
                        .tag(SidebarItem.project(item.project))
                }
            }
            Section("Next action", isExpanded: $showActions) {
                ForEach(NextAction.allCases, id: \.self) { action in
                    Label { HStack { Text(action.label); Spacer(); count(model.tabs(withAction: action).count) } } icon: { Image(systemName: action.symbol) }
                        .help(action.meaning)
                        .tag(SidebarItem.action(action))
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
        .safeAreaInset(edge: .bottom, spacing: 0) { LibraryStatus() }
    }

    private struct SourceRow { let id: String; let name: String; let symbol: String; let count: Int }

    private var sourceRows: [SourceRow] {
        var rows = [SourceRow(id: AppModel.allSourcesID, name: "All Sources", symbol: "square.stack.3d.up", count: model.allSourcesCount)]
        for d in model.devices where d.tabCount > 0 {
            rows.append(.init(id: d.id, name: d.name, symbol: "iphone", count: d.tabCount))
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

/// Shown when the tab database cannot be read.
private struct AccessView: View {
    @Environment(AppModel.self) private var model
    let error: CloudTabsReader.Failure

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield").font(.system(size: 40)).foregroundStyle(.secondary)
            Text(error.localizedDescription).font(.headline).multilineTextAlignment(.center)
            if case .noAccess = error {
                Text("In Full Disk Access, click + below the list, choose Sift in Applications, turn it on, then click Try Again.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Full Disk Access") { AppModel.openFullDiskAccessSettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Try Again") { model.reload() }
                }
            } else {
                Button("Try Again") { model.reload() }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Says when the current source has links that are in no theme yet (for
/// example right after adding Instagram or the Reading List), and offers the
/// two ways to sort them.
private struct UnsortedBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.unsortedCount
        if count > 0 || model.isSorting || model.isDiscovering {
            HStack(spacing: 10) {
                if model.isSorting {
                    ProgressView().controlSize(.small)
                    Text("Sorting with Claude: \(model.sortProgress.done) of \(model.sortProgress.total)")
                } else if model.isDiscovering {
                    ProgressView().controlSize(.small)
                    Text("Claude is reading all your links to find themes…")
                } else {
                    Image(systemName: "circle.dotted").foregroundStyle(.tint)
                    if model.themes.isEmpty {
                        Text("\(count) links, no themes yet. Claude reads them and proposes the themes you keep coming back to.")
                        Spacer()
                        Button("Discover Themes") { Task { await model.discoverThemes() } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("\(count) link\(count == 1 ? " is" : "s are") not in a theme yet (the grey cluster).")
                        Spacer()
                        Button("Discover Themes Again") { Task { await model.discoverThemes() } }
                            .buttonStyle(.borderedProminent)
                            .help("Claude reads every source together and may propose new themes. You review them first.")
                        Button("Sort into Current Themes") { Task { await model.sortUnsorted() } }
                            .help("Cheaper: Claude puts each link into one of the themes you have.")
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
                Spacer()
                Text("\(saved) of \(total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
