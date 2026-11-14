import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case unsorted
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
                    case .overview: NetworkView(selection: $selection)
                    case .unsorted: TabList(project: nil)
                    case .project(let name): TabList(project: name)
                    }
                }
            }
        }
        .toolbar { toolbar }
        .alert("Sorting stopped", isPresented: .init(get: { model.sortError != nil }, set: { if !$0 { model.sortError = nil } })) {
            Button("OK") { model.sortError = nil }
        } message: {
            Text(model.sortError ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Device", selection: .init(get: { model.state.deviceID ?? "" }, set: { model.selectDevice($0) })) {
                ForEach(model.devices) { d in Text("\(d.name) (\(d.tabCount))").tag(d.id) }
            }
            .pickerStyle(.menu)
            .disabled(model.devices.isEmpty)
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
                .help("Send the titles and URLs of unsorted tabs to Claude and sort them into projects.")
                .disabled(model.unsortedCount == 0)
            }
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

            Section("Projects") {
                ForEach(model.activeProjects, id: \.project) { item in
                    HStack { Text(item.project); Spacer(); count(item.count) }
                        .tag(SidebarItem.project(item.project))
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
