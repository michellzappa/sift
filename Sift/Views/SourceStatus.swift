import AppKit
import SwiftUI

// One home for the status of each source and the shared setup actions.
// Settings > Inputs and the Setup Guide both read these, so the two never
// disagree about what is connected.

/// A row for a source or an output: icon, name, one-line status and actions
/// on the right.
struct StatusRow<Actions: View>: View {
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

extension StatusRow where Actions == EmptyView {
    init(icon: String, name: String, status: String, warning: Bool = false) {
        self.init(icon: icon, name: name, status: status, warning: warning) { EmptyView() }
    }
}

extension AppModel {
    /// Safari's files are unreadable because Full Disk Access is off.
    var needsDiskAccess: Bool {
        if case .noAccess = loadError { return true }
        return false
    }

    var safariTabCount: Int { devices.reduce(0) { $0 + $1.tabCount } }

    var tabsStatus: String {
        if needsDiskAccess { return "Needs Full Disk Access" }
        if let loadError { return loadError.localizedDescription }
        return devices.isEmpty ? "No device syncs tabs" : "\(safariTabCount) tabs on \(devices.count) devices"
    }

    var readingListStatus: String {
        if needsDiskAccess { return "Needs Full Disk Access" }
        return readingListCount == 0 ? "No links" : "\(readingListCount) links"
    }

    var chromeTabCount: Int { chromeProfiles.reduce(0) { $0 + $1.tabs.count } }

    var chromeStatus: String {
        guard !chromeProfiles.isEmpty else {
            if ChromeHelper.installedBrowsers.isEmpty { return "No Chrome-based browser on this Mac" }
            return ChromeHelper.isInstalled ? "Helper installed. Waiting for the extension." : "Not set up"
        }
        let n = chromeProfiles.count
        var status = "\(chromeTabCount) tabs in \(n) \(n == 1 ? "profile" : "profiles")"
        let stale = chromeProfiles.filter(\.isStale)
        if let last = stale.map(\.updated).max() {
            status += ", \(stale.count) stale (last seen \(last.formatted(date: .abbreviated, time: .omitted)))"
        }
        return status
    }

    var chromeHasStale: Bool { chromeProfiles.contains(where: \.isStale) }

    var instagramStatus: String {
        guard state.instagramExportPath != nil else { return "No export chosen" }
        if instagramError != nil { return "Export not readable" }
        return "\(instagramCount) saved posts"
    }

    var xStatus: String {
        guard xConnected else { return "Not connected. Previews use oEmbed." }
        return "Connected as @\(state.xUsername ?? ""), \(xBookmarkIDs.count) bookmarks"
    }

    var importStatus: String {
        let files = state.importedSources
        guard !files.isEmpty else { return "No files imported" }
        let links = files.reduce(0) { $0 + (importCounts[$1.id] ?? 0) }
        return "\(files.count) \(files.count == 1 ? "file" : "files"), \(links) links"
    }

    /// Imported Google Takeout files (LinkImporter names them "YouTube").
    var youtubeImports: [LinkImporter.Source] { state.importedSources.filter { $0.name.hasPrefix("YouTube") } }

    var youtubeStatus: String {
        let files = youtubeImports
        guard !files.isEmpty else { return "No Takeout imported" }
        let links = files.reduce(0) { $0 + (importCounts[$1.id] ?? 0) }
        return "\(links) videos"
    }

    /// At least one source has links: Discover Themes has something to read.
    var hasReadableSource: Bool { allSourcesCount > 0 || !tabs.isEmpty }

    /// The chosen Claude backend can run: Claude Code is installed, or an
    /// API key is in the keychain.
    var claudeReady: Bool {
        switch state.backend {
        case .claudeCode: ClaudeCodeRunner.executable != nil
        case .api: Keychain.readKey() != nil
        }
    }

    /// Asks for a folder in an Obsidian vault and adds it as a destination.
    func addObsidianDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Send Here"
        panel.message = "Choose a folder in your Obsidian vault. Each sent link becomes one note there."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addDestination(Destination(kind: "obsidian", name: url.lastPathComponent, detail: url.path(percentEncoded: false),
                                   config: ["folder": url.path(percentEncoded: false)]))
    }
}

/// Install Chrome Helper and the two steps after it. Settings > Inputs and
/// the Setup Guide both show these.
struct ChromeHelperButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button(ChromeHelper.isInstalled ? "Install Again" : "Install Chrome Helper") { model.installChromeHelper() }
            Button("Show Extension Folder") { ChromeHelper.revealExtension() }
            Button("Copy Folder Path") { model.copy(ChromeHelper.extensionFolder.path(percentEncoded: false)) }
        }
    }
}

/// Sift's MCP server, sift-mcp, added to the user's own Claude Code.
enum MCPSetup {
    static var path: String { Bundle.main.bundleURL.appending(path: "Contents/MacOS/sift-mcp").path(percentEncoded: false) }
    static var command: String { "claude mcp add --scope user sift -- \(path)" }

    /// Runs `claude mcp add` and returns a message for the user.
    static func addToClaudeCode() async -> String {
        guard let claude = ClaudeCodeRunner.executable else { return "Claude Code was not found." }
        return await withCheckedContinuation { c in
            let p = Process()
            p.executableURL = claude
            p.arguments = ["mcp", "add", "--scope", "user", "sift", "--", path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { c.resume(returning: $0.terminationStatus == 0 ? "Added. Start a new Claude Code session to use it." : "Not added. It may be there already: run claude mcp list.") }
            do { try p.run() } catch { c.resume(returning: "Could not run Claude Code.") }
        }
    }
}
