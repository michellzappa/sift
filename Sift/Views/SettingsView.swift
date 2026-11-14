import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            InputSettings().tabItem { Label("Inputs", systemImage: "tray.and.arrow.down") }
            OutputSettings().tabItem { Label("Outputs", systemImage: "tray.and.arrow.up") }
            ClaudeSettings().tabItem { Label("Claude", systemImage: "sparkles") }
            ThemeSettings().tabItem { Label("Themes", systemImage: "circle.hexagongrid") }
        }
        .frame(width: 620, height: 560)
    }
}

/// The first row of a source or an output: icon, name, one-line status and
/// actions on the right.
private struct SourceRow<Actions: View>: View {
    let icon: String
    let name: String
    let status: String
    var warning = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
            Spacer()
            actions()
        }
    }
}

extension SourceRow where Actions == EmptyView {
    init(icon: String, name: String, status: String, warning: Bool = false) {
        self.init(icon: icon, name: name, status: status, warning: warning) { EmptyView() }
    }
}

private func abbreviated(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

// MARK: - Inputs

private struct InputSettings: View {
    @Environment(AppModel.self) private var model

    private var needsDiskAccess: Bool {
        if case .noAccess = model.loadError { return true }
        return false
    }

    private var tabsStatus: String {
        if needsDiskAccess { return "Needs Full Disk Access" }
        if let error = model.loadError { return error.localizedDescription }
        let total = model.devices.reduce(0) { $0 + $1.tabCount }
        return model.devices.isEmpty ? "No device syncs tabs" : "\(total) tabs on \(model.devices.count) devices"
    }

    private var readingListStatus: String {
        if needsDiskAccess { return "Needs Full Disk Access" }
        return model.readingListCount == 0 ? "No links" : "\(model.readingListCount) links"
    }

    private var instagramStatus: String {
        guard model.state.instagramExportPath != nil else { return "No export chosen" }
        if model.instagramError != nil { return "Export not readable" }
        return "\(model.instagramCount) saved posts"
    }

    private var xStatus: String {
        guard model.xConnected else { return "Not connected. Previews use oEmbed." }
        return "Connected as @\(model.state.xUsername ?? ""), \(model.xBookmarkIDs.count) bookmarks"
    }

    private var importStatus: String {
        let files = model.state.importedSources
        guard !files.isEmpty else { return "No files imported" }
        let links = files.reduce(0) { $0 + (model.importCounts[$1.id] ?? 0) }
        return "\(files.count) \(files.count == 1 ? "file" : "files"), \(links) links"
    }

    private var libraryStatus: String {
        let entries = model.library.values
        let thin = entries.filter { $0.status == "thin" }.count
        let failed = entries.filter { $0.status == "failed" }.count
        var line = "\(model.capturedCount) saved of \(model.archive.count), \(thin) thin, \(failed) failed"
        if model.isCapturing { line += ". Saving \(model.captureProgress.done) of \(model.captureProgress.total)." }
        return line
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                SourceRow(icon: "safari", name: "Safari tabs", status: tabsStatus, warning: model.loadError != nil) {
                    Button("Open Full Disk Access") { AppModel.openFullDiskAccessSettings() }
                }
                ForEach(model.devices) { d in
                    LabeledContent(d.name, value: "\(d.tabCount) tabs")
                }
                LabeledContent("Tab database") {
                    Text(abbreviated(CloudTabsReader.databaseURL.path(percentEncoded: false)))
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } footer: {
                Text("Open tabs that Safari syncs from your devices through iCloud. Sift reads them and never writes.")
                    .foregroundStyle(.secondary)
            }

            Section {
                SourceRow(icon: "eyeglasses", name: "Safari Reading List", status: readingListStatus, warning: needsDiskAccess)
            }

            Section {
                SourceRow(icon: "camera", name: "Instagram Saved", status: instagramStatus,
                          warning: model.state.instagramExportPath != nil && model.instagramError != nil) {
                    Button("Choose…") { model.chooseInstagramExport() }
                    if model.state.instagramExportPath != nil {
                        Button("Remove") { model.clearInstagramExport() }
                    }
                }
                if let path = model.state.instagramExportPath {
                    LabeledContent("Export") {
                        Text(abbreviated(path)).lineLimit(1).truncationMode(.middle)
                    }
                }
            } footer: {
                Text(model.instagramError ?? "Reads saved posts and collections from a JSON data export (Accounts Center, Download your information). Choose the zip or the folder it unpacks to.")
                    .foregroundStyle(.secondary)
            }

            Section {
                SourceRow(icon: "at", name: "X", status: xStatus)
                Toggle("Use X's embed data for post images (unofficial, may stop working)", isOn: .init(
                    get: { model.state.xSyndication },
                    set: { model.setXSyndication($0) }
                ))
                TextField("X app Client ID", text: $model.state.xClientID, prompt: Text("From the X Developer Console"))
                    .disabled(model.xConnected)
                HStack {
                    if model.xConnected {
                        Label("Connected as @\(model.state.xUsername ?? "")", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Spacer()
                        Button("Sync Bookmarks") { Task { await model.syncXBookmarks() } }.disabled(model.xBusy)
                        Button("Disconnect", role: .destructive) { model.disconnectX() }
                    } else {
                        Button("Connect X Account") { Task { await model.connectX() } }
                            .disabled(model.state.xClientID.isEmpty || model.xBusy)
                        if model.xBusy { ProgressView().controlSize(.small) }
                    }
                }
                if let error = model.xError { Text(error).font(.caption).foregroundStyle(.red) }
            } footer: {
                Text("Previews: with the embed data option off, X posts show text only, from X's public oEmbed endpoint. With it on, Sift asks X's syndication endpoint first, for the post image and the author's avatar.\n\nX API (optional, paid): shows posts natively and brings in your bookmarks, through your own X developer app. Create a Native App in the X Developer Console with callback URL \(XAuth.redirectURI) and the scopes tweet.read, users.read, bookmark.read and offline.access, then paste its Client ID here. X bills your developer account per post read (about $0.005). Sift caches posts and refreshes a post when it is older than a week.")
                    .foregroundStyle(.secondary)
            }

            Section {
                SourceRow(icon: "doc.text", name: "Imported files", status: importStatus) {
                    Button("Import Links File…") { model.importLinksFile() }
                }
                ForEach(model.state.importedSources) { source in
                    LabeledContent(source.name) {
                        HStack {
                            Text("\(model.importCounts[source.id] ?? 0) links · \(URL(filePath: source.path).lastPathComponent)")
                                .lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Remove") { model.removeImport(source) }
                        }
                    }
                }
                if let error = model.importError { Text(error).font(.caption).foregroundStyle(.red) }
            } footer: {
                Text("Instapaper or Pocket CSV, Readwise or Raindrop CSV, Pinboard JSON, or a bookmarks HTML file. Each file is its own source.")
                    .foregroundStyle(.secondary)
            }

            Section {
                SourceRow(icon: "books.vertical", name: "Library capture", status: libraryStatus) {
                    Button("Show Library in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Library.folder])
                    }
                }
                Toggle("Save the text of new links automatically", isOn: $model.state.autoCapture)
            } footer: {
                Text("Sift fetches each new link once and keeps its readable text as Markdown on this Mac. No Claude involved.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Outputs

private struct OutputSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showShortcutGuide = false

    private func icon(_ output: ExportOutput) -> String {
        switch output {
        case .folder: "folder"
        case .file: "doc"
        case .clipboard: "doc.on.clipboard"
        }
    }

    private var closeStatus: String {
        guard CloseList.iCloudDriveAvailable else { return "iCloud Drive is off" }
        let n = model.state.closeQueue.count
        return "iCloud Drive/Sift/close.txt, \(n) \(n == 1 ? "link" : "links") to close"
    }

    var body: some View {
        Form {
            Section {
                ForEach(Exporters.all, id: \.id) { exporter in
                    VStack(alignment: .leading, spacing: 4) {
                        SourceRow(icon: icon(exporter.output),
                                  name: exporter.name.replacingOccurrences(of: "…", with: ""),
                                  status: exporter.summary) {
                            Button("Run") { model.runExport(exporter) }
                        }
                        if let last = model.state.exportTargets[exporter.id] {
                            Text("Last: \(abbreviated(last))")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                                .padding(.leading, 34)
                        }
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Exports the sorted links of the current source. Drop, unknown, errands and unsorted links stay out.")
                    .foregroundStyle(.secondary)
            }

            Section {
                SourceRow(icon: "iphone", name: "iPhone close list", status: closeStatus,
                          warning: !CloseList.iCloudDriveAvailable) {
                    Button("Set Up Shortcut…") { showShortcutGuide = true }
                }
            } footer: {
                Text("A Mac cannot close tabs on another device. A Shortcut on the iPhone reads close.txt and closes the tabs.")
                    .foregroundStyle(.secondary)
            }

            Section {
                SourceRow(icon: "eyeglasses", name: "Add to Reading List",
                          status: "Cards and the browser add links through Safari. macOS asks once to allow Automation.") {
                    Button("Open Automation") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showShortcutGuide) { ShortcutGuide() }
    }
}

// MARK: - Claude

private struct ClaudeSettings: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var hasKey = Keychain.readKey() != nil

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Sort with", selection: $model.state.backend) {
                    ForEach(Sorter.Backend.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text(model.state.backend == .claudeCode
                     ? (ClaudeCodeRunner.executable == nil ? "Claude Code was not found in ~/.local/bin or Homebrew." : "Uses your Claude Code login. No API key needed.")
                     : "Uses the API key below, billed to your Anthropic API account.")
                    .foregroundStyle(.secondary)
            }
            Section {
                SecureField("Anthropic API key", text: $key, prompt: Text(hasKey ? "Saved in the keychain" : "sk-ant-…"))
                HStack {
                    Button("Save Key") { Keychain.saveKey(key); key = ""; hasKey = Keychain.readKey() != nil }
                        .disabled(key.isEmpty)
                    if hasKey {
                        Button("Remove Key", role: .destructive) { Keychain.saveKey(""); hasKey = false }
                    }
                }
            } footer: {
                Text("Sift sends the title, URL and preview text of each unsorted tab, and your project names and descriptions, to Claude. The key stays in your login keychain.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSettings: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var newSummary = ""
    @State private var editing: String?
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                if model.themes.isEmpty {
                    Text("No themes yet. Discover Themes reads all your links and proposes them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.projects) { theme in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            if editing == theme.name {
                                TextField("Name", text: $draft)
                                    .onSubmit { model.renameTheme(theme.name, to: draft); editing = nil }
                            } else {
                                Text(theme.name)
                            }
                            if !theme.summary.isEmpty {
                                Text(theme.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text("\(model.count(theme.name))").monospacedDigit().foregroundStyle(.secondary)
                        Button { draft = theme.name; editing = theme.name } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                            .help("Rename")
                        Button(role: .destructive) { model.removeTheme(theme.name) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Delete the theme. Its links become unsorted.")
                    }
                }
            } header: {
                Text("Themes")
            } footer: {
                Button("Discover Themes Again") { Task { await model.discoverThemes() } }
                    .disabled(model.isDiscovering || model.isSorting)
            }
            Section("Add a theme by hand") {
                TextField("Name", text: $newName)
                TextField("What it is about (helps Claude sort)", text: $newSummary)
                Button("Add Theme") {
                    model.addTheme(name: newName, summary: newSummary)
                    newName = ""; newSummary = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}
