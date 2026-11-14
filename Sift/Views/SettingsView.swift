import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            InputSettings().tabItem { Label("Inputs", systemImage: "tray.and.arrow.down") }
            LibrarySettings().tabItem { Label("Library", systemImage: "books.vertical") }
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

        }
        .formStyle(.grouped)
    }
}

// MARK: - Library

/// What Sift saves on this Mac, and the switches for each kind.
private struct LibrarySettings: View {
    @Environment(AppModel.self) private var model
    @State private var diskUse = ""

    var body: some View {
        @Bindable var model = model
        let entries = model.library.values
        let thin = entries.filter { $0.status == "thin" }.count
        let failed = entries.filter { $0.status == "failed" }.count
        let gone = entries.filter { $0.status == "gone" }.count
        Form {
            Section {
                Toggle("Save the text of every link", isOn: $model.state.autoCapture)
                LabeledContent("Saved", value: "\(model.capturedCount) of \(model.archive.count) links")
                LabeledContent("Thin (paywall or login)", value: "\(thin)")
                LabeledContent("Failed", value: "\(failed)")
                LabeledContent("Gone (page or site no longer exists)", value: "\(gone)")
                if model.isCapturing {
                    ProgressView(value: Double(model.captureProgress.done), total: Double(max(model.captureProgress.total, 1))) {
                        Text("Saving \(model.captureProgress.done) of \(model.captureProgress.total)").font(.caption)
                    }
                }
                HStack {
                    Button("Retry Failed") { Task { await model.retryFailedCaptures() } }
                        .disabled(failed == 0 || model.isCapturing)
                    Spacer()
                }
            } header: {
                Text("Page text")
            } footer: {
                Text("Each link is fetched once and kept as a Markdown file with its URL, title, author, site and theme. Sites are paced, and a site that asks to slow down is skipped for an hour. No Claude involved.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Save YouTube transcripts", isOn: $model.state.youtubeTranscripts)
                LabeledContent("Transcripts", value: TranscriptTool.executable == nil ? "Tool not installed" : "\(model.transcriptCount) saved")
                if model.isTranscribing {
                    ProgressView(value: Double(model.transcriptProgress.done), total: Double(max(model.transcriptProgress.total, 1))) {
                        Text("Fetching \(model.transcriptProgress.done) of \(model.transcriptProgress.total)").font(.caption)
                    }
                }
                if TranscriptTool.executable == nil {
                    HStack {
                        Button("Install Transcript Tool") { Task { await model.installTranscriptTool() } }
                        if let m = model.transcriptToolMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } header: {
                Text("YouTube")
            } footer: {
                Text("Uses the open-source youtube-transcript-api tool, newest saves first. It reads YouTube's captions in a way YouTube has not sanctioned and can stop working.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Save Instagram post images", isOn: $model.state.instagramImages)
                LabeledContent("Images", value: "\(model.instagramImageCount) saved")
                if model.isFetchingInstagramImages {
                    ProgressView(value: Double(model.instagramImageProgress.done), total: Double(max(model.instagramImageProgress.total, 1))) {
                        Text("Fetching \(model.instagramImageProgress.done) of \(model.instagramImageProgress.total)").font(.caption)
                    }
                }
                Toggle("Save what reels say", isOn: $model.state.reelTranscripts)
                LabeledContent("Reel transcripts", value: ReelTool.executable == nil ? "Tool not installed" : "\(model.reelTranscriptCount) of \(model.reelCount) reels")
                if model.isTranscribingReels {
                    ProgressView(value: Double(model.reelProgress.done), total: Double(max(model.reelProgress.total, 1))) {
                        Text("Transcribing \(model.reelProgress.done) of \(model.reelProgress.total)").font(.caption)
                    }
                }
                if ReelTool.executable == nil || model.reelToolMessage != nil {
                    HStack {
                        if ReelTool.executable == nil {
                            Button("Install Reel Tool") { Task { await model.installReelTool() } }
                        }
                        if let m = model.reelToolMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } header: {
                Text("Instagram")
            } footer: {
                Text("Images come from Instagram's public embed and stay on this Mac because Instagram's image links expire. Reel speech: the open-source yt-dlp tool fetches the audio without a login, macOS speech recognition turns it into text (on this Mac where the language allows), and the audio is deleted.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Size on disk", value: diskUse.isEmpty ? "…" : diskUse)
                HStack {
                    Button("Show Library in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Library.folder]) }
                    Spacer()
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("~/Library/Application Support/Sift: Library (page text and transcripts), Images (Instagram) and Imports (copies of your exports).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { diskUse = await Self.size() }
    }

    /// Size of Sift's saved files, measured off the main thread.
    static func size() async -> String {
        await Task.detached {
            let root = StateFile.url.deletingLastPathComponent()
            var total: Int64 = 0
            if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
                while let f = walker.nextObject() as? URL {
                    total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }.value
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

    private func addObsidian() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Send Here"
        panel.message = "Choose a folder in your Obsidian vault. Each sent link becomes one note there."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addDestination(Destination(kind: "obsidian", name: url.lastPathComponent, detail: url.path(percentEncoded: false),
                                         config: ["folder": url.path(percentEncoded: false)]))
    }

    private func addMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "Links.md"
        panel.prompt = "Send Here"
        panel.message = "Sent links are added to the end of this file, one line each."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addDestination(Destination(kind: "markdown", name: url.deletingPathExtension().lastPathComponent, detail: url.path(percentEncoded: false),
                                         config: ["file": url.path(percentEncoded: false)]))
    }

    private var closeStatus: String {
        guard CloseList.iCloudDriveAvailable else { return "iCloud Drive is off" }
        let n = model.state.closeQueue.count
        return "iCloud Drive/Sift/close.txt, \(n) \(n == 1 ? "link" : "links") to close"
    }

    @State private var connecting = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(model.destinations) { d in
                    HStack {
                        d.image.frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.name)
                            if !d.detail.isEmpty { Text(d.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                        }
                        Spacer()
                        Text("\(model.sentTabs(to: d.id).count) sent").font(.caption).foregroundStyle(.secondary)
                        Button(role: .destructive) { model.removeDestination(d.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove this destination. Links already sent stay where they are.")
                    }
                }
                HStack {
                    Button("Connect Starlings…") { connecting = true }
                    Button("Add Obsidian Folder…") { addObsidian() }
                    Button("Add Markdown File…") { addMarkdown() }
                    if !model.destinations.contains(where: { $0.kind == "reading-list" }) {
                        Button("Add Reading List") { model.addDestination(Destination(kind: "reading-list", name: "Reading List", detail: "Safari")) }
                    }
                }
                Toggle("Close sent Safari tabs on iPhone", isOn: $model.state.closeAfterSend)
            } header: {
                Text("Send to")
            } footer: {
                Text("Send files a link at once. A theme can have a default destination: then one click sends there. Starlings files each link as a Docs link save on the project you pick, through your own Starlings sign-in.")
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $connecting) { StarlingsConnect().environment(model) }

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
            OnDeviceSection()
            Section {
                Toggle("Find links that feed two themes", isOn: $model.state.findConnections)
                if model.isConnecting {
                    ProgressView(value: Double(model.connectProgress.done), total: Double(max(model.connectProgress.total, 1))) {
                        Text("Checking \(model.connectProgress.done) of \(model.connectProgress.total)").font(.caption)
                    }
                }
            } header: {
                Text("Connections")
            } footer: {
                Text("After sorting, Claude checks 60 links at a time for a second or third theme they feed. The graph draws those as lines between themes.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Command") {
                    Text(Self.mcpCommand).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                }
                HStack {
                    Button("Add to Claude Code") { Task { mcpMessage = await Self.addToClaudeCode() } }
                        .disabled(ClaudeCodeRunner.executable == nil)
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.mcpCommand, forType: .string)
                    }
                    if let mcpMessage { Text(mcpMessage).font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Claude can read your library")
            } footer: {
                Text("Sift includes a small MCP server, sift-mcp. Claude Code and Claude Desktop can then search your saved links, page text and transcripts, list your themes and read a link in full. It only reads Sift's search index on this Mac. For Claude Desktop, add it as a server named sift with the path above as its command.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @State private var mcpMessage: String?

    static var mcpPath: String { Bundle.main.bundleURL.appending(path: "Contents/MacOS/sift-mcp").path(percentEncoded: false) }
    static var mcpCommand: String { "claude mcp add --scope user sift -- \(mcpPath)" }

    /// Runs `claude mcp add` for the user's own Claude Code.
    static func addToClaudeCode() async -> String {
        guard let claude = ClaudeCodeRunner.executable else { return "Claude Code was not found." }
        return await withCheckedContinuation { c in
            let p = Process()
            p.executableURL = claude
            p.arguments = ["mcp", "add", "--scope", "user", "sift", "--", mcpPath]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { c.resume(returning: $0.terminationStatus == 0 ? "Added. Start a new Claude Code session to use it." : "Not added. It may be there already: run claude mcp list.") }
            do { try p.run() } catch { c.resume(returning: "Could not run Claude Code.") }
        }
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
