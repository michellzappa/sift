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
                    switch selection ?? .overview {
                    case .overview: OverviewView(selection: $selection)
                    case let other: TabList(item: other).id(other)
                    }
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
                ForEach(model.devices) { d in Text("\(d.name) (\(d.tabCount))").tag(d.id) }
                if model.readingListCount > 0 {
                    Divider()
                    Text("Reading List (\(model.readingListCount))").tag(ReadingListReader.sourceID)
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
            if !model.isReadingList {
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
            Section("Not for a project") {
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

/// The overview: the hub layout or the force-directed graph.
private struct OverviewView: View {
    @Binding var selection: SidebarItem?
    @AppStorage("overview.style") private var style = "graph"

    var body: some View {
        Group {
            if style == "graph" { GraphView(selection: $selection) } else { NetworkView(selection: $selection) }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $style) {
                    Label("Graph", systemImage: "point.3.connected.trianglepath.dotted").tag("graph")
                    Label("Hubs", systemImage: "circle.hexagongrid").tag("hubs")
                }
                .pickerStyle(.segmented)
                .help("Graph: themes, links and sites as a network. Hubs: one circle per theme.")
            }
        }
    }
}
