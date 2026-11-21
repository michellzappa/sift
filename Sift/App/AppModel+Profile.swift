import Foundation

/// Settings > You (Engine/Profile.swift, Views/YouSettings.swift). Takes a
/// snapshot of what the model holds on the main actor, then reads the
/// per-device files (seen marks, signals) and file sizes off it and builds
/// the `Profile`. No network, no Claude. Every path derives from
/// `StateFile.url` or `CloseList.folder`, so demo mode reads demo data.
extension AppModel {
    func buildProfile() async -> Profile {
        // On the main actor: what is already in memory.
        var input = Profile.Inputs()
        let tabSource = Dictionary(tabs.map { ($0.url, $0.source) }, uniquingKeysWith: { a, _ in a })
        var names: [String: String] = [:]
        input.saved = savedLinks().map { link in
            let id = archive[link.url]?.source ?? tabSource[link.url] ?? ""
            let name = names[id] ?? profileSourceName(id)
            names[id] = name
            return Profile.Saved(url: link.url, source: name, date: link.date, theme: link.theme)
        }
        input.themeNames = themes.map(\.name)
        input.followedFeeds = state.feeds.count
        let hidden = Set(state.hiddenCreators)
        input.creators = creators.filter { !hidden.contains($0.id) }.count
        input.feedTitles = Dictionary(state.feeds.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

        // Modes, words and lengths Sift knows: library first, then Today.
        for (url, entry) in library {
            let words = entry.status == "ok" ? entry.words : 0
            if words > 0 { input.wordsOf[url] = words }
            if let d = entry.duration { input.durationOf[url] = d }
            input.modeOf[url] = entry.transcript == true || entry.duration != nil ? .watch : Modes.mode(url: url, words: words)
        }
        let feedsByID = Dictionary(state.feeds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for pick in todayPicks where input.modeOf[pick.url] == nil {
            input.modeOf[pick.url] = mode(of: pick, feeds: feedsByID)
            let words = Modes.words(pick.content)
            if words > 0 { input.wordsOf[pick.url] = words }
        }
        // A feed's own mode, else its provider's, for items no longer in Today.
        var feedModes: [String: (set: ReadingMode?, provider: ReadingMode?)] = [:]
        for feed in state.feeds {
            feedModes[feed.id] = (mode(of: feed), Modes.providerMode(feed.provider ?? AppModel.providerID(forFeed: feed.url)))
        }

        let paths = Self.profileFiles()
        let base = input
        let feedModes0 = feedModes

        // Off the main actor: device files, feed items and file sizes.
        return await Task.detached(priority: .utility) {
            var input = base
            let seenDecoder = JSONDecoder(); seenDecoder.dateDecodingStrategy = .iso8601
            let fm = FileManager.default
            func jsonFiles(_ dir: URL) -> [URL] {
                ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
            }
            var devices = Set<String>()

            for file in jsonFiles(SeenStore.folder) {
                devices.insert(file.deletingPathExtension().lastPathComponent)
                guard let data = try? Data(contentsOf: file),
                      let marks = try? seenDecoder.decode([String: SeenMark].self, from: data) else { continue }
                let device = Profile.device(ofFile: file.lastPathComponent)
                for (url, mark) in marks where mark.seen {
                    input.seen.append((url, Profile.Moment(device: device, at: mark.at)))
                }
            }
            for file in jsonFiles(TodayStore.deviceFolder) {
                devices.insert(file.deletingPathExtension().lastPathComponent)
            }
            let local = FeedSignals.loadLocal()
            if !local.isEmpty { devices.insert(SeenStore.deviceFile.replacingOccurrences(of: ".json", with: "")) }
            input.signals = local.map { ($0, "mac") }
            for file in jsonFiles(FeedSignals.deviceFolder) {
                devices.insert(file.deletingPathExtension().lastPathComponent)
                guard let data = try? Data(contentsOf: file),
                      let events = try? seenDecoder.decode([SignalEvent].self, from: data) else { continue }
                let device = Profile.device(ofFile: file.lastPathComponent)
                input.signals += events.map { ($0, device) }
            }
            input.devices = devices.map(Self.deviceName)

            // Feed items behind signals that left Today: their words and mode.
            let signalFeeds = Set(input.signals.map(\.event.feedID)).filter { !$0.isEmpty }
            let wanted = Set(input.signals.map(\.event.url)).filter { input.modeOf[$0] == nil }
            if !wanted.isEmpty {
                for id in signalFeeds {
                    for entry in FeedStore.entries(id) where wanted.contains(entry.url) && input.modeOf[entry.url] == nil {
                        let words = Modes.words(entry.content ?? entry.summary)
                        if words > 0 { input.wordsOf[entry.url] = words }
                        let modes = feedModes0[id]
                        input.modeOf[entry.url] = Modes.isVideo(entry.url) ? .watch
                            : modes?.set ?? Modes.mode(url: entry.url, words: words, provider: modes?.provider)
                    }
                }
            }

            input.files = paths.map { item in
                let path = item.url.path(percentEncoded: false)
                return Profile.DataFile(name: item.name, path: path, bytes: Self.size(of: item.url),
                                        exists: fm.fileExists(atPath: path), note: item.note)
            }
            return Profile.build(input)
        }.value
    }

    /// The display name of a saved link's source, grouped: every Safari
    /// device is "Safari tabs", every import keeps its own name.
    private func profileSourceName(_ id: String) -> String {
        if id.hasPrefix("tabs:") || id == "tabs" || devices.contains(where: { $0.id == id }) { return "Safari tabs" }
        if id.hasPrefix(ChromeReader.sourcePrefix) {
            return chromeProfiles.contains { $0.id == id } ? sourceTitle(id) : "Chrome"
        }
        if id == "reading-list" || id == ReadingListReader.sourceID { return "Reading List" }
        if id == "instagram" || id == InstagramReader.sourceID { return "Instagram Saved" }
        if id == TikTokReader.sourceID { return "TikTok" }
        if id == "x" || id == AppModel.xBookmarksSourceID { return "X Bookmarks" }
        if id == TodayStore.keptSourceID { return "Kept from Today" }
        if id.hasPrefix(Self.listPrefix) {
            return state.feeds.first { Self.listPrefix + $0.id == id }.map { "List: \($0.title)" } ?? "Lists"
        }
        if id.hasPrefix(LinkImporter.sourcePrefix) {
            return state.importedSources.first { LinkImporter.sourcePrefix + $0.id == id }.map { "Import: \($0.name)" } ?? "Imports"
        }
        return "Other"
    }

    /// The files and folders Sift owns, each from its own constant.
    static func profileFiles() -> [(name: String, url: URL, note: String)] {
        [
            ("Sift folder", StateFile.url.deletingLastPathComponent(), "Everything below, plus backups and tools"),
            ("state.json", StateFile.url, "Themes, sorting, feeds you follow, settings, Today"),
            ("archive.json", ArchiveStore.url, "Every link Sift has seen, with its source and first date"),
            ("previews.json", PreviewFetcher.cacheURL, "Titles, preview text and images of links"),
            ("Library", Library.folder, "One Markdown file per link: page text, transcripts, summaries"),
            ("Images", InstagramImageFetcher.folder, "Saved pictures of Instagram and TikTok posts"),
            ("search.sqlite", SearchIndex.url, "The search index that sift-mcp reads"),
            ("Feeds", FeedStore.folder, "Items from the feeds you follow"),
            ("x-posts.json", XStore.url, "Text of saved X posts"),
            ("signals.json", FeedSignals.localURL, "What you did with Today picks on this Mac"),
            ("farther.json", Farther.fileURL, "Claude's suggestions per theme, with the prompt it saw"),
            ("subclusters.json", SubClusterStore.fileURL, "The parts of each theme and their names"),
            ("Telemetry", Telemetry.folder, "The weekly report waiting to go out, and its secret"),
            ("iCloud Drive/Sift", CloseList.folder, "Shared with your iPhone: close list, Today, kept, follows"),
            ("Seen marks", SeenStore.folder, "Seen and unseen, one file per device"),
            ("Signals from devices", FeedSignals.deviceFolder, "What you did with Today picks on your iPhone"),
        ]
    }

    /// Bytes in a file, or in every file below a folder.
    nonisolated static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        func bytes(_ u: URL) -> Int64 {
            let v = try? u.resourceValues(forKeys: keys)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        guard isDir.boolValue else { return bytes(url) }
        var total: Int64 = 0
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let file as URL in walker where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                total += bytes(file)
            }
        }
        return total
    }

    /// "mac-1a2b" → "Mac 1a2b", "iphone-9f3c" → "iPhone 9f3c".
    nonisolated static func deviceName(_ id: String) -> String {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        let kind = parts.first?.lowercased() ?? ""
        let label = switch kind {
        case "mac": "Mac"
        case "iphone": "iPhone"
        case "ipad": "iPad"
        default: kind.capitalized
        }
        return parts.count > 1 ? "\(label) \(parts[1])" : label
    }
}

/// Settings > You on the iPhone: the Mac writes the profile to
/// iCloud Drive/Sift/Deck/you.json once a day.
extension AppModel {
    func writeProfileForPhone(force: Bool = false) async {
        let key = "profile.phoneWritten"
        guard !Demo.isOn, CloseList.iCloudDriveAvailable else { return }
        if !force, let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        let profile = await buildProfile()
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(profile) else { return }
        let dir = CloseList.folder.appending(path: "Deck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "you.json"), options: .atomic)
        UserDefaults.standard.set(Date(), forKey: key)
    }
}
