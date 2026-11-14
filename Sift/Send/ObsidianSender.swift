import Foundation

/// One note per link in a folder of an Obsidian vault (or any folder):
/// front matter, your note, the summary and the text Sift saved.
struct ObsidianSender: Sender {
    let kind = "obsidian"
    let label = "Obsidian"
    let symbol = "doc.text"

    func send(_ item: SendItem, to destination: Destination) async throws -> String? {
        guard let path = destination.config["folder"] else { throw SendFailure(message: "This Obsidian destination has no folder.") }
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
            throw SendFailure(message: "The folder \(folder.lastPathComponent) is not there any more.")
        }
        let file = folder.appending(path: Self.fileName(item.title.isEmpty ? item.url : item.title) + ".md")
        let iso = ISO8601DateFormatter()
        var lines = ["---", "url: \(item.url)", "title: \"\(item.title.replacingOccurrences(of: "\"", with: "'"))\""]
        if !item.theme.isEmpty { lines.append("theme: \"\(item.theme)\"") }
        lines += ["source: \(item.source)", "site: \(item.site)"]
        if let saved = item.saved { lines.append("saved: \(iso.string(from: saved))") }
        lines += ["sent: \(iso.string(from: .now))", "tags: [sift]", "---", "", "# \(item.title.isEmpty ? item.url : item.title)", "", item.url, ""]
        if !item.note.isEmpty { lines += ["> \(item.note)", ""] }
        if !item.summary.isEmpty { lines += [item.summary, ""] }
        if !item.text.isEmpty { lines += ["## Saved text", "", item.text, ""] }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file.path(percentEncoded: false)
    }

    /// A safe, short file name from a title.
    static func fileName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]").union(.newlines).union(.controlCharacters)
        let clean = title.components(separatedBy: bad).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        return String(clean.prefix(90)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
    }
}
