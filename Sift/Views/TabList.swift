import SwiftUI

/// The tabs in one project or bucket. `project == nil` means unsorted.
struct TabList: View {
    @Environment(AppModel.self) private var model
    let project: String?
    @State private var search = ""

    private var rows: [SafariTab] {
        let all = model.tabs(in: project)
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search)
                || (model.assignment(for: $0)?.use.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        List(rows) { tab in
            TabRow(tab: tab)
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(project == nil ? "Nothing left to sort" : "No tabs here", systemImage: "checkmark.circle")
            }
        }
        .searchable(text: $search, prompt: "Filter")
        .navigationTitle(project ?? "Unsorted")
        .navigationSubtitle(summary)
        .toolbar {
            if let project {
                ToolbarItem {
                    Button { model.copy(model.markdown(for: project)) } label: {
                        Label("Copy as Markdown", systemImage: "doc.on.doc")
                    }
                    .help("Copy this project's links and uses as a Markdown list.")
                }
            }
        }
    }

    private var summary: String {
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.displayTitle).lineLimit(2)
                if let use = a?.use, !use.isEmpty {
                    Text(use).font(.callout).foregroundStyle(.tint)
                }
                HStack(spacing: 6) {
                    Text(tab.host)
                    if let d = tab.lastViewed { Text("·"); Text(d, format: .dateTime.day().month().year()) }
                    if a?.manual == true { Text("·"); Image(systemName: "hand.point.up.left").help("Sorted by hand") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                moveMenu
            } label: {
                Text(a?.project ?? "Move to…")
            }
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

    private func open() {
        guard let url = URL(string: tab.url) else { return }
        let safari = URL(filePath: "/Applications/Safari.app")
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
    }
}
