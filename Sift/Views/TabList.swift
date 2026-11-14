import AppKit
import SwiftUI

/// The tabs in one sidebar item: unsorted, a project or bucket, or the close list.
struct TabList: View {
    @Environment(AppModel.self) private var model
    let item: SidebarItem
    @State private var search = ""
    @State private var selected: SafariTab.ID?
    @State private var showInspector = true
    @State private var showShortcutGuide = false

    private var project: String? {
        if case .project(let p) = item { return p }
        return nil
    }

    private var title: String {
        switch item {
        case .overview: "Overview"
        case .unsorted: "Unsorted"
        case .closeQueue: "To close on iPhone"
        case .project(let p): p
        }
    }

    private var all: [SafariTab] {
        switch item {
        case .overview: model.tabs
        case .unsorted: model.tabs(in: nil)
        case .closeQueue: model.closeQueueTabs
        case .project(let p): model.tabs(in: p)
        }
    }

    private var rows: [SafariTab] {
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search)
                || (model.assignment(for: $0)?.use.localizedCaseInsensitiveContains(search) ?? false)
                || (model.previews[$0.url]?.text.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if item == .closeQueue { closeHeader }
            List(rows, selection: $selected) { tab in
                TabRow(tab: tab).tag(tab.id)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(item == .unsorted ? "Nothing left to sort" : "No tabs here", systemImage: "checkmark.circle")
            }
        }
        .searchable(text: $search, prompt: "Filter")
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .inspector(isPresented: $showInspector) {
            Group {
                if let tab = rows.first(where: { $0.id == selected }) {
                    PreviewPane(tab: tab)
                } else {
                    ContentUnavailableView("Select a tab", systemImage: "sidebar.right", description: Text("Its preview shows here."))
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
        }
        .toolbar { listToolbar }
        .sheet(isPresented: $showShortcutGuide) { ShortcutGuide() }
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItemGroup {
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
            if item != .closeQueue, !rows.isEmpty {
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
            Button { showInspector.toggle() } label: { Label("Preview", systemImage: "sidebar.right") }
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

    private var subtitle: String {
        let n = rows.count
        let text = model.projects.first(where: { $0.name == project })?.summary ?? ""
        return "\(n) tab\(n == 1 ? "" : "s")" + (text.isEmpty ? "" : " · \(text.prefix(80))")
    }
}

struct TabRow: View {
    @Environment(AppModel.self) private var model
    let tab: SafariTab
    @State private var editingUse = false
    @State private var draft = ""

    var body: some View {
        let a = model.assignment(for: tab)
        let preview = model.previews[tab.url]
        let closing = model.isQueuedToClose(tab)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle(preview)).lineLimit(2).strikethrough(closing, color: .secondary)
                if let use = a?.use, !use.isEmpty {
                    Text(use).font(.callout).foregroundStyle(.tint)
                } else if !tab.hasUsefulTitle, let text = preview?.text, !text.isEmpty {
                    Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(tab.host)
                    if let d = tab.lastViewed { Text("·"); Text(d, format: .dateTime.day().month().year()) }
                    if a?.manual == true { Text("·"); Image(systemName: "hand.point.up.left").help("Sorted by hand") }
                    if closing { Text("·"); Label("closes on iPhone", systemImage: "xmark.square").labelStyle(.titleAndIcon) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu { moveMenu } label: { Text(a?.project ?? "Move to…") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
        .contextMenu {
            Button("Open in Safari") { open() }
            Button("Copy Link") { model.copy(tab.url) }
            if a != nil, !Project.buckets.contains(a?.project ?? "") {
                Button("Edit Use…") { draft = a?.use ?? ""; editingUse = true }
            }
            Divider()
            Button(closing ? "Keep Open on iPhone" : "Close on iPhone") { model.toggleClose(tab) }
            Menu("Move to") { moveMenu }
            Button("Drop") { model.move(tab, to: Project.drop) }
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

    private func rowTitle(_ preview: Preview?) -> String {
        if tab.hasUsefulTitle { return tab.title }
        if let p = preview, !p.failed, !p.title.isEmpty { return p.site == "x.com" ? "\(p.title) on X" : p.title }
        return tab.url
    }

    @ViewBuilder
    private var moveMenu: some View {
        ForEach(model.projects) { p in
            Button(p.name) { model.move(tab, to: p.name) }
        }
        Divider()
        ForEach(Project.buckets, id: \.self) { b in
            Button(b) { model.move(tab, to: b) }
        }
    }

    private func open() { TabActions.openInSafari(tab.url) }
}

enum TabActions {
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
                    if !a.use.isEmpty { Text(a.use).foregroundStyle(.tint) }
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

    private let steps = [
        "Open Shortcuts on the iPhone and create a new shortcut named \"Sift: Close Tabs\".",
        "Add \"Get File\". Turn off \"Show Document Picker\" and set the path to Sift/close.txt in iCloud Drive.",
        "Add \"Get Text from Input\" so the file becomes text.",
        "Add \"Find Tabs\" (Safari) with no filter, so it returns every open tab.",
        "Add \"Repeat with Each\" on the found tabs.",
        "Inside the repeat, add \"If\": the text from step 3 contains the Repeat Item's URL.",
        "Inside the If, add \"Close Tab\" with the Repeat Item.",
        "Run the shortcut. Then click Reload in Sift: closed tabs leave the list.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Close tabs on the iPhone").font(.title2.weight(.semibold))
            Text("A Mac cannot close tabs on another device, so Sift writes the close list to iCloud Drive and a Shortcut on the iPhone closes them. You build the Shortcut once.")
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 18, alignment: .trailing)
                    Text(step)
                }
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
