import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case unsorted
    case closeQueue
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
        .alert("Export", isPresented: .init(get: { model.exportMessage != nil }, set: { if !$0 { model.exportMessage = nil } })) {
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
            }
            .pickerStyle(.menu)
            .disabled(model.devices.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            if model.isDiscovering {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Finding themes…")
                }
            } else {
                Button {
                    Task { await model.discoverThemes() }
                } label: {
                    Label("Discover Themes", systemImage: "circle.hexagongrid.circle")
                }
                .help("Ask Claude to find the themes in all your tabs and Reading List. You review them before anything changes.")
                .disabled(model.isSorting)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if model.isSorting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(model.sortProgress.done)/\(model.sortProgress.total)").monospacedDigit()
                }
            } else {
                Button {
                    Task { await model.sortUnsorted() }
                } label: {
                    Label("Sort \(model.unsortedCount) with Claude", systemImage: "sparkles")
                }
                .help(model.themes.isEmpty ? "Discover your themes first." : "Sort unsorted tabs into your themes with Claude.")
                .disabled(model.unsortedCount == 0 || model.themes.isEmpty)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if !model.isSorting, !model.tabsWithoutAction.isEmpty {
                Button {
                    Task { await model.suggestActions() }
                } label: {
                    Label("Suggest Next Actions", systemImage: "arrow.forward.circle")
                }
                .help("Ask Claude what to do next with \(model.tabsWithoutAction.count) sorted tabs that have no next action.")
            }
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

    var body: some View {
        List(selection: $selection) {
            Label("Overview", systemImage: "circle.hexagongrid").tag(SidebarItem.overview)
            Label { HStack { Text("Unsorted"); Spacer(); count(model.unsortedCount) } } icon: { Image(systemName: "tray") }
                .tag(SidebarItem.unsorted)
            if !model.isSavedList {
                Label { HStack { Text("To close on iPhone"); Spacer(); count(model.state.closeQueue.count) } } icon: { Image(systemName: "xmark.square") }
                    .tag(SidebarItem.closeQueue)
            }

            Section("Themes") {
                ForEach(model.activeProjects, id: \.project) { item in
                    HStack { Text(item.project); Spacer(); count(item.count) }
                        .tag(SidebarItem.project(item.project))
                }
            }
            Section("Next action") {
                ForEach(NextAction.allCases, id: \.self) { action in
                    Label { HStack { Text(action.label); Spacer(); count(model.tabs(withAction: action).count) } } icon: { Image(systemName: action.symbol) }
                        .help(action.meaning)
                        .tag(SidebarItem.action(action))
                }
            }
            Section("Sites") {
                ForEach(model.sites, id: \.host) { site in
                    HStack { Text(site.host).lineLimit(1); Spacer(); count(site.count) }
                        .tag(SidebarItem.site(site.host))
                }
            }
            Section("Outside your themes") {
                ForEach(Project.buckets, id: \.self) { bucket in
                    HStack { Text(bucket); Spacer(); count(model.count(bucket)) }
                        .tag(SidebarItem.project(bucket))
                }
            }
        }
        .listStyle(.sidebar)
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
