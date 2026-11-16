import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    // MARK: Instagram Saved

    /// True when the source is Instagram's saved posts from the data export.
    var isInstagram: Bool { state.deviceID == InstagramReader.sourceID }

    func instagramItems() -> [InstagramReader.Item] {
        guard let path = state.instagramExportPath else { instagramError = nil; return [] }
        do {
            let items = try InstagramReader.items(at: path)
            instagramError = nil
            return items
        } catch {
            instagramError = error.localizedDescription
            return []
        }
    }

    /// Asks for the Instagram export (the zip or its unpacked folder) and shows it as a source.
    func chooseInstagramExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.prompt = "Choose"
        panel.message = "Choose your Instagram export: the zip, or the folder it unpacks to."
        if let last = state.instagramExportPath { panel.directoryURL = URL(filePath: last).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.instagramExportPath = Self.keepCopy(of: url).path(percentEncoded: false)
        reload()
    }

    func clearInstagramExport() {
        state.instagramExportPath = nil
        reload()
    }

    /// True when the source is a saved list (Reading List, Instagram Saved),
    /// not a device's open tabs. Saved lists have nothing to close on the iPhone.
    // MARK: Archive

    /// The source key a link is recorded under: "tabs:<device>",
    /// "reading-list", "instagram", "x" or "import:<id>".
    var currentSourceKey: String {
        if isReadingList { return "reading-list" }
        if isInstagram { return "instagram" }
        if isTikTok { return "tiktok" }
        if isXBookmarks { return "x" }
        if let list = currentList { return Self.listPrefix + list.id }
        if let profile = currentChrome { return profile.id }
        if let source = currentImport { return LinkImporter.sourcePrefix + source.id }
        return "tabs:\(state.deviceID ?? "")"
    }

    /// The sources whose full list is loaded right now, so a record missing
    /// from them really left (and is not just in another source).
    private var loadedSourceKeys: Set<String> {
        guard isAll else { return [currentSourceKey] }
        var keys: Set<String> = ["reading-list", "instagram", "tiktok", "x"]
        if let phone = devices.first { keys.insert("tabs:\(phone.id)") }
        for p in chromeProfiles { keys.insert(p.id) }
        for s in state.importedSources { keys.insert(LinkImporter.sourcePrefix + s.id) }
        for f in myLists { keys.insert(Self.listPrefix + f.id) }
        return keys
    }

    /// Records every link the current view shows, and archives the records
    /// of links that left a loaded source. Called on every reload.
    func recordArchive() {
        let now = Date()
        let present = Set(tabs.map(\.url))
        for tab in tabs {
            var r = archive[tab.url] ?? ArchiveRecord(url: tab.url, title: tab.title, source: tab.source, firstSeen: tab.lastViewed ?? now)
            let p = previews[tab.url]
            if tab.hasUsefulTitle { r.title = tab.title } else if let p, !p.failed, !p.title.isEmpty { r.title = p.title }
            if let a = state.assignments[tab.url] { r.theme = a.project; r.use = a.use }
            if let p, !p.failed { r.previewText = p.text; r.imageURL = p.imageURL ?? p.avatarURL }
            r.lastSeen = now
            r.archived = nil
            archive[tab.url] = r
        }
        let loaded = loadedSourceKeys
        for (url, r) in archive where r.archived == nil && loaded.contains(r.source) && !present.contains(url) {
            archive[url]?.archived = now
        }
        ArchiveStore.save(archive)
        // Archived links show from their record when no preview is cached.
        for r in archive.values where r.isArchived && previews[r.url] == nil && !r.previewText.isEmpty {
            previews[r.url] = Preview(title: r.title, text: r.previewText, imageURL: r.imageURL, site: r.asTab.host, fetched: r.lastSeen)
        }
    }

    /// Links that left their source, newest first.
    var archivedTabs: [SafariTab] {
        archive.values.filter(\.isArchived).sorted { ($0.archived ?? .distantPast) > ($1.archived ?? .distantPast) }.map(\.asTab)
    }

    func archiveRecord(for url: String) -> ArchiveRecord? { archive[url] }
}
