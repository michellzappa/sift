import Foundation

/// Seen and unseen (Storage/Seen.swift). A link is unseen until someone opens
/// it on any device or marks it; the newest mark from any device wins.
extension AppModel {
    func isSeen(_ url: String) -> Bool { seenMarks[url]?.seen ?? false }

    func unseenCount(_ tabs: [SafariTab]) -> Int { tabs.reduce(0) { $0 + (isSeen($1.url) ? 0 : 1) } }

    func setSeen(_ urls: [String], _ seen: Bool) {
        let now = Date()
        var changed = false
        for url in urls where isSeen(url) != seen {
            let mark = SeenMark(seen: seen, at: now)
            ownSeen[url] = mark
            seenMarks[url] = mark
            changed = true
        }
        guard changed else { return }
        scheduleSeenSave()
    }

    /// Reads every device's file again: on reload, with the library jobs and
    /// when Sift comes to the front.
    func loadSeen() {
        let (merged, own) = SeenStore.load()
        // Keep marks made here that are not on disk yet.
        var mine = own
        for (url, mark) in ownSeen where (mine[url]?.at ?? .distantPast) < mark.at { mine[url] = mark }
        var all = merged
        for (url, mark) in mine where (all[url]?.at ?? .distantPast) < mark.at { all[url] = mark }
        ownSeen = mine
        if all != seenMarks { seenMarks = all }
        // Kept items from the phone travel the same way.
        mergeDeviceKept()
    }

    private func scheduleSeenSave() {
        seenSaveTask?.cancel()
        seenSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            SeenStore.save(self.ownSeen)
        }
    }
}
