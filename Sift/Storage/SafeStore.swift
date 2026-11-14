import Foundation

/// Loads and saves Sift's own data files (state, archive, previews, the
/// library index) so a file that cannot be read is never overwritten.
///
/// - Every save first keeps an hourly copy in `Backups/` (the last 24 per
///   file).
/// - A file that exists but does not decode is copied aside as
///   `<name>.unreadable-<date>.json`, and the newest backup that decodes is
///   used instead. If no backup decodes, saving that file stays off for this
///   run, so Sift cannot replace the user's data with an empty one.
/// - A save that would shrink a large file to under a tenth of its size is
///   refused and reported: no edit in Sift loses that much at once.
enum SafeStore {
    /// What went wrong this run, for a message in the app.
    static var problems: [String] { lock.withLock { _problems } }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _problems: [String] = []
    nonisolated(unsafe) private static var blocked = Set<String>()
    nonisolated(unsafe) private static var lastBackup: [String: Date] = [:]

    private static var backups: URL { StateFile.url.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory) }

    /// The decoded file, a recovered backup, or nil when the file is absent
    /// (first run) or nothing could be read.
    static func load<T: Decodable>(_ url: URL, as type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> T? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        if let data = try? Data(contentsOf: url), let value = try? decoder.decode(T.self, from: data) { return value }

        // Unreadable: keep a copy, then try the backups, newest first.
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? fm.copyItem(at: url, to: aside)
        let name = url.deletingPathExtension().lastPathComponent
        for backup in backupFiles(for: name).reversed() {
            if let data = try? Data(contentsOf: backup), let value = try? decoder.decode(T.self, from: data) {
                report("Sift could not read \(url.lastPathComponent) and restored the copy from \(backup.lastPathComponent). The unreadable file is kept as \(aside.lastPathComponent).")
                return value
            }
        }
        lock.withLock { _ = blocked.insert(url.path(percentEncoded: false)) }
        report("Sift could not read \(url.lastPathComponent) and found no backup it could read. It will not save over that file this time. The file is kept as \(aside.lastPathComponent).")
        return nil
    }

    /// Writes atomically after keeping an hourly backup of the current file.
    static func save(_ data: Data, to url: URL) {
        let path = url.path(percentEncoded: false)
        if lock.withLock({ blocked.contains(path) }) { return }
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > 64_000, data.count < size / 10 {
            report("Sift did not save \(url.lastPathComponent): the new version was much smaller than the old one (\(data.count) bytes instead of \(size)). Nothing was lost.")
            return
        }
        backup(url)
        try? data.write(to: url, options: .atomic)
    }

    private static func backup(_ url: URL) {
        let path = url.path(percentEncoded: false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        let due = lock.withLock { () -> Bool in
            if let last = lastBackup[path], Date().timeIntervalSince(last) < 3600 { return false }
            lastBackup[path] = .now
            return true
        }
        guard due else { return }
        try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
        let name = url.deletingPathExtension().lastPathComponent
        let hour = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        let copy = backups.appending(path: "\(name)-\(hour).json")
        try? fm.removeItem(at: copy)
        try? fm.copyItem(at: url, to: copy)
        for old in backupFiles(for: name).dropLast(24) { try? fm.removeItem(at: old) }
    }

    /// Backups of one file, oldest first (the names sort by date).
    private static func backupFiles(for name: String) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix(name + "-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func report(_ message: String) {
        lock.withLock { _problems.append(message) }
    }
}
