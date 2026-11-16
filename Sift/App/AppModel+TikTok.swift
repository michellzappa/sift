import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    // MARK: TikTok (issue #25)

    /// True when the source is TikTok favourites (and likes) from the data export.
    var isTikTok: Bool { state.deviceID == TikTokReader.sourceID }

    func tiktokItems() -> [TikTokReader.Item] {
        guard let path = state.tiktokExportPath else { tiktokError = nil; tiktokCounts = .init(); return [] }
        do {
            let (items, counts) = try TikTokReader.items(at: path, likes: state.tiktokLikes)
            tiktokError = nil
            tiktokCounts = counts
            return items
        } catch {
            tiktokError = error.localizedDescription
            tiktokCounts = .init()
            return []
        }
    }

    /// Asks for the TikTok export (the zip, its folder or the JSON file) and shows it as a source.
    func chooseTikTokExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.zip, .folder, .json]
        panel.prompt = "Choose"
        panel.message = "Choose your TikTok export: the zip, the folder it unpacks to, or user_data_tiktok.json."
        if let last = state.tiktokExportPath { panel.directoryURL = URL(filePath: last).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.tiktokExportPath = Self.keepCopy(of: url).path(percentEncoded: false)
        reload()
    }

    func clearTikTokExport() {
        state.tiktokExportPath = nil
        reload()
    }

    var tiktokStatus: String {
        guard state.tiktokExportPath != nil else { return "No export chosen" }
        if tiktokError != nil { return "Export not readable" }
        var parts = ["\(tiktokCounts.favorites) favourites"]
        if tiktokCounts.likes > 0 { parts.append("\(tiktokCounts.likes) likes" + (state.tiktokLikes ? "" : " (off)")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Video details

    /// TikTok links (any source) without a caption, author or cover yet, newest first.
    var tiktokNeedingDetails: [String] {
        guard !isBlocked("tiktok") else { return [] }
        return archive.values
            .filter { r in
                guard TikTokReader.videoID(r.url) != nil, !tiktokTried.contains(r.url) else { return false }
                let p = previews[r.url]
                return p == nil || p?.imageURL == nil && (p?.title ?? "").isEmpty
            }
            .sorted { $0.firstSeen > $1.firstSeen }
            .map(\.url)
    }

    /// One video page at a time (HostGate: 4 s apart). A check page or 429
    /// pauses the job with the doubling wait.
    func fetchTikTokDetails() async {
        guard !Demo.isOn, !isFetchingTikTok else { return }
        let todo = tiktokNeedingDetails
        guard !todo.isEmpty else { return }
        isFetchingTikTok = true
        tiktokProgress = (0, todo.count)
        defer { isFetchingTikTok = false; PreviewFetcher.saveCache(previews); ArchiveStore.save(archive); scheduleSearchIndex() }
        for url in todo {
            tiktokTried.insert(url)
            switch await TikTokPage.fetch(url) {
            case .throttled:
                tiktokTried.remove(url)
                block("tiktok")
                return
            case .gone:
                var p = previews[url] ?? Preview(title: "", text: "", imageURL: nil, site: "tiktok.com", fetched: .now)
                p.title = "TikTok video (no longer public)"
                p.fetched = .now
                previews[url] = p
            case .details(let d):
                unblock("tiktok")
                let note = previews[url]?.text.hasPrefix("Liked") == true ? "Liked on TikTok." : nil
                var text = d.caption
                if let note, text.isEmpty { text = note }
                let title = d.author.isEmpty ? (d.username.isEmpty ? "TikTok" : "@\(d.username)") : "\(d.author) (@\(d.username))"
                previews[url] = Preview(title: title, text: text, imageURL: d.cover, site: "tiktok.com", fetched: .now)
                if var r = archive[url] {
                    r.title = title
                    r.previewText = text
                    r.imageURL = d.cover
                    archive[url] = r
                }
            }
            tiktokProgress.done += 1
            if tiktokProgress.done % 10 == 0 { PreviewFetcher.saveCache(previews) }
        }
    }
}
