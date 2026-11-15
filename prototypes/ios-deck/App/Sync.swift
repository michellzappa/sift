import Foundation

/// Seen and unseen, the same files as Sift on the Mac (Sift/Storage/Seen.swift):
/// iCloud Drive/Sift/seen/<device>.json, one file per device, newest mark
/// per URL wins. The phone reaches iCloud Drive/Sift through a folder the
/// user picks once; a security-scoped bookmark keeps the access.
struct SeenMark: Codable, Sendable, Equatable {
    var seen: Bool
    var at: Date
}

/// Reads a file in iCloud Drive through NSFileCoordinator, which makes iCloud
/// download it first if only a placeholder is on the phone.
func coordinatedData(_ url: URL) -> Data? {
    var result: Data?
    var error: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &error) { real in
        result = try? Data(contentsOf: real)
    }
    return result
}

/// Copies a file out of iCloud Drive the same way.
func coordinatedCopy(_ from: URL, to: URL) -> Bool {
    var ok = false
    var error: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: from, options: [], error: &error) { real in
        try? FileManager.default.removeItem(at: to)
        ok = (try? FileManager.default.copyItem(at: real, to: to)) != nil
    }
    return ok
}

extension Store {
    private static let bookmarkKey = "siftFolderBookmark"
    private static let deviceKey = "seenDeviceID"

    static var deviceFile: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return "iphone-\(id).json" }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        UserDefaults.standard.set(id, forKey: deviceKey)
        return "iphone-\(id).json"
    }

    private static var ownSeenURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "seen-own.json")
    }

    static var coder: (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    static func loadOwnSeen() -> [String: SeenMark] {
        guard let data = try? Data(contentsOf: ownSeenURL) else { return [:] }
        return (try? coder.1.decode([String: SeenMark].self, from: data)) ?? [:]
    }

    // MARK: Today and kept

    private static var keptURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "kept-here.json")
    }
    private static var todayURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "today.json")
    }

    static func loadKeptHere() -> [KeptItem] {
        guard let data = try? Data(contentsOf: keptURL) else { return [] }
        return (try? coder.1.decode([KeptItem].self, from: data)) ?? []
    }

    static func loadToday() -> TodayFile? {
        guard let data = try? Data(contentsOf: todayURL) else { return nil }
        return try? coder.1.decode(TodayFile.self, from: data)
    }

    func isKept(_ url: String) -> Bool {
        keptHere.contains { $0.url == url } || (today?.kept.contains(url) ?? false)
    }

    /// Keeps an offered item. The Mac picks it up from kept/iphone-<id>.json
    /// and moves it into its library.
    func keep(_ pick: TodayPick) {
        guard !isKept(pick.url) else { return }
        keptHere.append(KeptItem(url: pick.url, title: pick.title, date: pick.date, kept: Date(), feedID: pick.feedID,
                                 feedTitle: pick.feedTitle, summary: pick.summary, image: pick.image))
        record(pick.item, .keep, mode: "today", position: 0)
        setSeen([pick.item], true, mode: "today")
        saveKept()
    }

    private func saveKept() {
        guard let data = try? Self.coder.0.encode(keptHere) else { return }
        try? data.write(to: Self.keptURL, options: .atomic)
        withFolder { folder in
            let dir = folder.appending(path: "kept", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appending(path: Self.deviceFile), options: .atomic)
        }
    }

    // MARK: Seen

    func isSeen(_ url: String) -> Bool { seenMarks[url]?.seen ?? false }

    func unseenCount(theme: String) -> Int {
        deck.items.filter { $0.theme == theme && !isSeen($0.url) }.count
    }

    func setSeen(_ items: [Item], _ seen: Bool, mode: String) {
        let now = Date()
        for item in items where isSeen(item.url) != seen {
            let mark = SeenMark(seen: seen, at: now)
            ownSeen[item.url] = mark
            seenMarks[item.url] = mark
            record(item, seen ? .seen : .unseen, mode: mode, position: 0)
            // An unseen mark on a Today pick is a signal for the Mac's ranking.
            if !seen, let pick = today?.picks.first(where: { $0.url == item.url }) { signal(.unseen, pick) }
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            self.saveSeen()
        }
    }

    private func saveSeen() {
        guard let data = try? Self.coder.0.encode(ownSeen) else { return }
        try? data.write(to: Self.ownSeenURL, options: .atomic)
        withFolder { folder in
            let dir = folder.appending(path: "seen", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appending(path: Self.deviceFile), options: .atomic)
        }
    }

    // MARK: The iCloud Drive/Sift folder

    /// The user picked iCloud Drive/Sift (or its Deck folder) in Files.
    func connect(folder url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var root = url
        if url.lastPathComponent == "Deck" { root = url.deletingLastPathComponent() }
        guard let bookmark = try? root.bookmarkData() else {
            error = "Could not keep access to that folder."
            return
        }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        sync()
    }

    /// Runs `body` with the connected folder open, if there is one.
    @discardableResult
    func withFolder(_ body: (URL) -> Void) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return false }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey) }
        connectedFolder = url.lastPathComponent
        body(url)
        return true
    }

    /// Reads the Deck (if newer) and every device's seen file, and writes
    /// this phone's marks. On launch, when the app comes to the front, and
    /// from the Lists tab's pull to refresh.
    func sync() {
        let fm = FileManager.default
        let decoder = Self.coder.1
        withFolder { folder in
            // Ask iCloud to bring down anything still in the cloud.
            for name in ["Deck/deck.json", "seen"] {
                try? fm.startDownloadingUbiquitousItem(at: folder.appending(path: name))
            }
            // The Deck folder replaces the imported deck when it is newer.
            let deckURL = folder.appending(path: "Deck/deck.json")
            let date = (try? deckURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if deck.demo || date > (UserDefaults.standard.object(forKey: "deckDate") as? Date ?? .distantPast) {
                // Only a deck that really loaded counts as done.
                if importDeck(from: folder.appending(path: "Deck", directoryHint: .isDirectory)) {
                    UserDefaults.standard.set(date, forKey: "deckDate")
                }
            }
            var merged = ownSeen
            let dir = folder.appending(path: "seen", directoryHint: .isDirectory)
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "json" {
                guard let data = coordinatedData(file),
                      let marks = try? decoder.decode([String: SeenMark].self, from: data) else { continue }
                for (url, mark) in marks where (merged[url]?.at ?? .distantPast) < mark.at { merged[url] = mark }
            }
            seenMarks = merged
            // Today from the Mac.
            if let data = coordinatedData(folder.appending(path: "Deck/today.json")),
               let file = try? decoder.decode(TodayFile.self, from: data) {
                today = file
                try? data.write(to: Self.todayURL, options: .atomic)
            }
            if !keptHere.isEmpty, let data = try? Self.coder.0.encode(keptHere) {
                let dir = folder.appending(path: "kept", directoryHint: .isDirectory)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: dir.appending(path: Self.deviceFile), options: .atomic)
            }
            writeSignals(to: folder)
            if let data = try? Self.coder.0.encode(ownSeen), !ownSeen.isEmpty {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: dir.appending(path: Self.deviceFile), options: .atomic)
            }
        }
    }
}
