import HouseKit
import SwiftUI

/// Settings in the house shell (HouseKit `HouseSettingsView`, the Headroom
/// shape): General first, Sift's own panes, About last. A new pane is one
/// more `SettingsPane` in `panes`.
struct SettingsView: View {
    /// Demo mode can open on a given pane (`-demoView settings:<pane>`).
    @State private var navigation = SettingsNavigation(selection: Demo.settingsTab ?? SettingsPane.generalID)

    var body: some View {
        HouseSettingsView(appName: "Sift", panes: panes, navigation: navigation, floats: false)
    }

    private var panes: [SettingsPane] {
        [
            .general { GeneralSettings() },
            SettingsPane(id: "inputs", title: "Inputs", symbol: "tray.and.arrow.down") { InputSettings() },
            SettingsPane(id: "library", title: "Library", symbol: "books.vertical") { LibrarySettings() },
            SettingsPane(id: "outputs", title: "Outputs", symbol: "tray.and.arrow.up") { OutputSettings() },
            SettingsPane(id: "intelligence", title: "Intelligence", symbol: "sparkles") { ClaudeSettings() },
            SettingsPane(id: "themes", title: "Themes", symbol: "circle.hexagongrid") { ThemeSettings() },
            SettingsPane(id: "privacy", title: "Privacy", symbol: "hand.raised") { PrivacySettings() },
            .about {
                AboutSettingsPane(
                    appName: "Sift",
                    tagline: "What you save, sorted into themes, kept on your Mac.",
                    credit: "Created by Michell Zappa",
                    repository: "michellzappa/sift",
                    links: [AboutLink("Community Pulse", url: Telemetry.communityURL)]
                )
            },
        ]
    }
}

private func abbreviated(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

// MARK: - General

/// The house General pane: launch at login, updates, then the Setup Guide
/// and version history.
private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GeneralSettingsPane(updates: UpdateChecker.shared) {
            Section {
                HStack {
                    Button("Open Setup Guide") {
                        model.startSetupGuide()
                        openWindow(id: Onboarding.windowID)
                    }
                    Button("Version History") { openWindow(id: VersionHistory.windowID) }
                }
            } footer: {
                Text("The Setup Guide walks through sources, Claude and your first themes again. Version History lists what changed in every release.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Privacy

/// The anonymous diagnostics switch, with the exact batch it allows.
private struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var on = Telemetry.enabled
    @State private var showBatch = false

    var body: some View {
        Form {
            Section {
                Toggle("Share anonymous usage counts", isOn: $on)
                    .disabled(Demo.isOn)
                    .onChange(of: on) { _, value in Telemetry.setEnabled(value) }
                HStack {
                    Button("Show What Is Sent") { showBatch.toggle() }
                    Link("Community Pulse", destination: Telemetry.communityURL)
                    Link("Privacy Contract", destination: Telemetry.contractURL)
                }
                if showBatch {
                    Text(batchJSON)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("Once a week, Sift sends one small report: the app and macOS version, which kinds of source and destination you use, which switches are on, and rough sizes such as \"100-999 links\". It never sends a link, title, theme name, note, account or file path. It sends no install id: the key that stops a Mac from counting twice changes every week. The totals are public on the Community Pulse page.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var batchJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(TelemetryCoordinator.shared.preview(model)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Inputs

private struct InputSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            // Feeds first: the primary input.
            FeedSettings()

            Section {
                StatusRow(icon: "safari", name: "Safari tabs", status: model.tabsStatus, warning: model.loadError != nil) {
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
                StatusRow(icon: "eyeglasses", name: "Safari Reading List", status: model.readingListStatus, warning: model.needsDiskAccess)
            }

            ChromeSettings()

            Section {
                StatusRow(icon: "camera", name: "Instagram Saved", status: model.instagramStatus,
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
                StatusRow(icon: "at", name: "X", status: model.xStatus)
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
                StatusRow(icon: "doc.text", name: "Imported files", status: model.importStatus) {
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

// MARK: - Chrome

/// Chrome profiles that report their tabs through Sift's extension.
private struct ChromeSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            StatusRow(icon: "globe", name: "Chrome", status: model.chromeStatus, warning: model.chromeHasStale)
            ForEach(model.chromeProfiles) { p in
                LabeledContent {
                    HStack {
                        Text("\(p.tabs.count) tabs, updated \(p.updated.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(p.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        Button("Remove") { model.removeChromeProfile(p) }
                    }
                } label: {
                    TextField(p.browser, text: .init(get: { model.state.chromeProfileNames[p.install] ?? "" },
                                                     set: { model.setChromeProfileName($0, for: p) }),
                              prompt: Text(model.chromeProfileName(p) ?? "Name this profile"))
                }
            }
            ChromeHelperButtons()
            if let message = model.chromeHelperMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        } footer: {
            Text("A small extension sends the open tabs of each Chrome profile to Sift on this Mac and closes the tabs you mark here. It does not read pages or use the internet. The helper also works in Brave, Edge, Arc, Vivaldi and Chromium. To add the extension, open chrome://extensions, turn on Developer mode, click Load unpacked and choose the extension folder. In that window, Command-Shift-G lets you paste the folder path.")
                .foregroundStyle(.secondary)
        }
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
                Toggle("When YouTube refuses captions, transcribe the audio on this Mac", isOn: $model.state.youtubeAudio)
                    .disabled(ReelTool.executable == nil)
                    .help(ReelTool.executable == nil ? "Needs the reel tool (yt-dlp): install it under Instagram below." : "Downloads the audio, turns it into text with macOS speech recognition on this Mac, then deletes the audio. Videos over 90 minutes are skipped.")
                LabeledContent("Transcripts", value: TranscriptTool.executable == nil ? "Tool not installed" : "\(model.transcriptCount) saved")
                if let until = model.state.blockedUntil["youtube"], until > .now {
                    Text("YouTube is refusing requests from this network for now. Sift tries again at \(until.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                if let until = model.state.blockedUntil["reels"], until > .now {
                    Text("Instagram is refusing requests from this network for now. Sift tries again at \(until.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        let n = model.iPhoneCloseQueue.count
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
                    Button("Add Obsidian Folder…") { model.addObsidianDestination() }
                    Button("Add Markdown File…") { addMarkdown() }
                    if !model.destinations.contains(where: { $0.kind == "reading-list" }) {
                        Button("Add Reading List") { model.addDestination(Destination(kind: "reading-list", name: "Reading List", detail: "Safari")) }
                    }
                }
                Toggle("Close sent tabs on the iPhone and in Chrome", isOn: $model.state.closeAfterSend)
            } header: {
                Text("Send to")
            } footer: {
                Text("Sending is immediate. If a theme has a default destination, one click on the plane sends there. Starlings saves each link to your Links in that workspace's Docs, signed in as you.")
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $connecting) { StarlingsConnect().environment(model) }

            Section {
                ForEach(Exporters.all, id: \.id) { exporter in
                    VStack(alignment: .leading, spacing: 4) {
                        StatusRow(icon: icon(exporter.output),
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
                StatusRow(icon: "iphone", name: "iPhone close list", status: closeStatus,
                          warning: !CloseList.iCloudDriveAvailable) {
                    Button("Set Up Shortcut…") { showShortcutGuide = true }
                }
            } footer: {
                Text("A Mac cannot close tabs on another device. A Shortcut on the iPhone reads close.txt and closes the tabs.")
                    .foregroundStyle(.secondary)
            }

            Section {
                StatusRow(icon: "eyeglasses", name: "Add to Reading List",
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
                    Text(MCPSetup.command).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                }
                HStack {
                    Button("Add to Claude Code") { Task { mcpMessage = await MCPSetup.addToClaudeCode() } }
                        .disabled(ClaudeCodeRunner.executable == nil)
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(MCPSetup.command, forType: .string)
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
