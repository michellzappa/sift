import Foundation

/// Seen and unseen, like read and unread in mail, shared by every device
/// through plain files: iCloud Drive/Sift/seen/<device>.json. Each device
/// writes only its own file (URL → mark); every device reads all of them,
/// and for each URL the newest mark wins. No server, and no two devices
/// write the same file, so iCloud never has a conflict to resolve.
struct SeenMark: Codable, Sendable, Equatable {
    var seen: Bool
    var at: Date
}

enum SeenStore {
    static var folder: URL { CloseList.folder.appending(path: "seen", directoryHint: .isDirectory) }

    /// This Mac's file name: "mac-<random id>", kept in UserDefaults so it
    /// survives a reinstall of the state file but not a new Mac.
    static var deviceFile: String {
        let key = "seenDeviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return "mac-\(id).json" }
        let id = UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return "mac-\(id).json"
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    /// Every device's marks, merged: newest mark per URL. Also returns this
    /// Mac's own marks, so a save never drops what another device wrote.
    static func load() -> (merged: [String: SeenMark], own: [String: SeenMark]) {
        let fm = FileManager.default
        let (_, decoder) = coder()
        var merged: [String: SeenMark] = [:]
        var own: [String: SeenMark] = [:]
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let marks = try? decoder.decode([String: SeenMark].self, from: data) else { continue }
            if file.lastPathComponent == deviceFile { own = marks }
            for (url, mark) in marks where (merged[url]?.at ?? .distantPast) < mark.at {
                merged[url] = mark
            }
        }
        return (merged, own)
    }

    static func save(_ own: [String: SeenMark]) {
        guard CloseList.iCloudDriveAvailable else { return }
        let (encoder, _) = coder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(own) else { return }
        let file = folder.appending(path: deviceFile)
        if (try? Data(contentsOf: file)) == data { return }
        try? data.write(to: file, options: .atomic)
    }
}
