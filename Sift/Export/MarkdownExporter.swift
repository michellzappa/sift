import Foundation

/// One Markdown file: a section per theme, a bullet per link with its use.
struct MarkdownExporter: Exporter {
    let id = "markdown"
    let name = "Markdown File…"
    let summary = "One Markdown file with a section per theme and a bullet per link."
    let output = ExportOutput.file(extension: "md")

    func export(_ snapshot: ExportSnapshot, to destination: URL?) throws -> String {
        let text = Self.render(snapshot)
        guard let destination else { return text }
        try text.write(to: destination, atomically: true, encoding: .utf8)
        return "Wrote \(snapshot.items.count) links to \(destination.lastPathComponent)."
    }

    static func render(_ snapshot: ExportSnapshot) -> String {
        var lines = ["# Sift export, \(ExportText.day.string(from: snapshot.created))", ""]
        for theme in snapshot.themes.sorted(by: { $0.count > $1.count }) {
            lines += ["## \(theme.name)", ""]
            if !theme.summary.isEmpty { lines += [theme.summary, ""] }
            for item in snapshot.items(in: theme.name) {
                let title = item.title.isEmpty ? item.url : item.title
                var line = "- [\(title.replacingOccurrences(of: "]", with: ")"))](\(item.url))"
                if !item.sentTo.isEmpty { line += " → \(item.sentTo.joined(separator: ", "))" }
                if !item.use.isEmpty { line += ": \(item.use)" }
                lines.append(line)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// The same Markdown, to the clipboard.
struct MarkdownClipboardExporter: Exporter {
    let id = "markdown-clipboard"
    let name = "Copy as Markdown"
    let summary = "The Markdown export, copied to the clipboard."
    let output = ExportOutput.clipboard

    func export(_ snapshot: ExportSnapshot, to destination: URL?) throws -> String {
        MarkdownExporter.render(snapshot)
    }
}
