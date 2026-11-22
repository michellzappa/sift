import Foundation

/// The Downloads watcher (issue #43, ADR 0001 decision 10). Off until the
/// person turns it on in Settings > Inputs (macOS asks for access to
/// Downloads then). A new Instagram, TikTok or X export or a Google Takeout
/// zip is known by its contents (`FollowingReader.kind`), copied into
/// Sift's Imports folder (`keepCopy`) and read. Sift never deletes or moves
/// the file in Downloads.
extension AppModel {
    nonisolated static var downloadsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// Files older than this are not imported when the watcher starts.
    nonisolated static let downloadsWindowDays: Double = 60

    /// Starts or stops the watcher to match the switch.
    func startDownloadsWatcher() {
        downloadsSource?.cancel()
        downloadsSource = nil
        downloadsScan?.cancel()
        guard !Demo.isOn, state.following.watchDownloads else { return }
        let fd = open(Self.downloadsFolder.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else {
            note("Sift cannot read Downloads. Allow it in System Settings > Privacy & Security > Files and Folders.")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in Task { @MainActor in self?.scheduleDownloadsScan() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        downloadsSource = source
        scheduleDownloadsScan(after: 1)
    }

    func setWatchDownloads(_ on: Bool) {
        state.following.watchDownloads = on
        startDownloadsWatcher()
    }

    /// A download writes many events: scan once, a few seconds after the last.
    func scheduleDownloadsScan(after seconds: Double = 5) {
        downloadsScan?.cancel()
        downloadsScan = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.scanDownloads()
        }
    }

    /// Imports the newest new export per network, when it is newer than the
    /// one Sift has.
    func scanDownloads() async {
        guard !Demo.isOn, state.following.watchDownloads else { return }
        var current: [String: Date] = [:]
        for n in FollowNetwork.allCases where n.isExport {
            if let src = followingSource(n), let d = ExportFile.date(of: src) { current[n.rawValue] = d }
        }
        let folder = Self.downloadsFolder
        let done = state.following.fromDownloads
        let checked = downloadsChecked
        let (found, nowChecked) = await Task.detached(priority: .utility) {
            Self.findExports(in: folder, done: done, checked: checked, current: current)
        }.value
        downloadsChecked = nowChecked
        guard !found.isEmpty else { return }
        for f in found { importExport(f.network, from: URL(filePath: f.path), date: f.date) }
        reload()
    }

    struct FoundExport: Sendable {
        var network: FollowNetwork
        var path: String
        var date: Date
    }

    nonisolated static func findExports(in folder: URL, done: [String: Date], checked: [String: Date],
                                        current: [String: Date]) -> ([FoundExport], [String: Date]) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        var checked = checked
        var best: [FollowNetwork: FoundExport] = [:]
        for f in files {
            let ext = f.pathExtension.lowercased()
            guard ext == "zip" || ext == "json" else { continue }
            let path = f.path(percentEncoded: false)
            guard let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date().timeIntervalSince(date) < downloadsWindowDays * 86_400,
                  done[path] != date, checked[path] != date else { continue }
            let kind: FollowNetwork?
            if ext == "json" {
                kind = f.lastPathComponent.lowercased().hasPrefix("user_data") ? .tiktok : nil
            } else {
                let members = ExportFile.members(path)
                // No members: not a complete zip yet. Look again on the next event.
                if members.isEmpty { continue }
                kind = FollowingReader.kind(members: members)
            }
            guard let kind else { checked[path] = date; continue }
            if let have = current[kind.rawValue], date <= have { checked[path] = date; continue }
            if best[kind].map({ date > $0.date }) ?? true { best[kind] = FoundExport(network: kind, path: path, date: date) }
        }
        return (best.values.sorted { $0.date < $1.date }, checked)
    }

    /// Copies the export into Imports and points the network at the copy.
    func importExport(_ n: FollowNetwork, from url: URL, date: Date) {
        let copy = Self.keepCopy(of: url).path(percentEncoded: false)
        // The copy keeps the download's date: staleness reads it.
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: copy)
        switch n {
        case .instagram: state.instagramExportPath = copy
        case .tiktok: state.tiktokExportPath = copy
        case .x: state.following.xArchivePath = copy
        case .youtube: setTakeout(copy)
        case .bluesky, .mastodon: return
        }
        state.following.fromDownloads[url.path(percentEncoded: false)] = date
        if exportReminder == n { exportReminder = nil }
        note("Imported your new \(n.name) export from Downloads")
    }
}
