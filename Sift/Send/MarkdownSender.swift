import Foundation

/// One line per link at the end of a Markdown file.
struct MarkdownSender: Sender {
    let kind = "markdown"
    let label = "Markdown File"
    let symbol = "list.bullet.rectangle"

    func send(_ item: SendItem, to destination: Destination) async throws -> String? {
        guard let path = destination.config["file"] else { throw SendFailure(message: "This destination has no file.") }
        let file = URL(filePath: path)
        var line = "- [\(item.title.isEmpty ? item.url : item.title.replacingOccurrences(of: "]", with: ")"))](\(item.url))"
        if !item.theme.isEmpty { line += " · \(item.theme)" }
        if !item.note.isEmpty { line += " — \(item.note.replacingOccurrences(of: "\n", with: " "))" }
        line += "\n"
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try line.write(to: file, atomically: true, encoding: .utf8)
        }
        return file.path(percentEncoded: false)
    }
}
