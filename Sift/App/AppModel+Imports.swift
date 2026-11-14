import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    // MARK: Imported link files

    var currentImport: LinkImporter.Source? {
        guard let id = state.deviceID, id.hasPrefix(LinkImporter.sourcePrefix) else { return nil }
        return state.importedSources.first { LinkImporter.sourcePrefix + $0.id == id }
    }

    func importedItems(_ source: LinkImporter.Source) -> [LinkImporter.Item] {
        (try? LinkImporter.items(at: source.path)) ?? []
    }

    /// Asks for an export file (CSV, JSON or bookmark HTML), checks that it
    /// has links, adds it as a source and switches to it.
    func importLinksFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json, .html, .plainText, .zip, .folder]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose an export from Instapaper, Pocket, Readwise, Raindrop, Pinboard, a bookmarks file, or a Google Takeout zip with YouTube playlists."
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        let path = Self.keepCopy(of: picked).path(percentEncoded: false)
        do {
            _ = try LinkImporter.items(at: path)
            let source = LinkImporter.Source(id: UUID().uuidString, name: LinkImporter.suggestedName(for: path), path: path, added: .now)
            state.importedSources.append(source)
            importError = nil
            state.deviceID = LinkImporter.sourcePrefix + source.id
            reload()
        } catch {
            importError = error.localizedDescription
            sortError = error.localizedDescription
        }
    }

    /// Copies a chosen export into ~/Library/Application Support/Sift/Imports
    /// so it keeps working after the original is moved or deleted. Falls back
    /// to the original when the copy fails.
    static func keepCopy(of url: URL) -> URL {
        let dir = StateFile.url.deletingLastPathComponent().appending(path: "Imports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appending(path: url.lastPathComponent)
        if url.standardizedFileURL == target.standardizedFileURL { return url }
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return url
        }
    }

    func removeImport(_ source: LinkImporter.Source) {
        state.importedSources.removeAll { $0.id == source.id }
        if currentImport == nil, state.deviceID?.hasPrefix(LinkImporter.sourcePrefix) == true { state.deviceID = Self.allSourcesID }
        reload()
    }
}
