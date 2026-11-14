import Foundation

/// Writes an Obsidian-ready folder: one note per link and one note per
/// theme, joined with [[wikilinks]], so Obsidian's graph view shows themes as
/// hubs and links as nodes.
///
/// Layout inside the chosen folder (a vault or any folder in one):
///   Sift/Themes/<theme>.md
///   Sift/Links/<title>.md
///   Sift/Sift.md            (index)
///
/// Sift owns these files and rewrites them on every export. Anything you
/// write under a "## Notes" heading in a link or theme note is kept.
struct ObsidianExporter: Exporter {
    let id = "obsidian"
    let name = "Obsidian Vault…"
    let summary = "One note per link and per theme with [[wikilinks]] and frontmatter, for Obsidian's graph view."
    let output = ExportOutput.folder

    private static let notesHeading = "## Notes"

    func export(_ snapshot: ExportSnapshot, to destination: URL?) throws -> String {
        guard let destination else { return "No folder chosen." }
        let fm = FileManager.default
        let root = destination.appending(path: "Sift", directoryHint: .isDirectory)
        let themesDir = root.appending(path: "Themes", directoryHint: .isDirectory)
        let linksDir = root.appending(path: "Links", directoryHint: .isDirectory)
        try fm.createDirectory(at: themesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: linksDir, withIntermediateDirectories: true)

        // Unique note names for links; two pages can share a title.
        var used = Set<String>()
        var noteName: [String: String] = [:]
        for item in snapshot.items {
            var base = ExportText.fileName(item.title.isEmpty ? item.site : item.title)
            if used.contains(base.lowercased()) { base += " (\(item.site))" }
            var name = base
            var n = 2
            while used.contains(name.lowercased()) { name = "\(base) \(n)"; n += 1 }
            used.insert(name.lowercased())
            noteName[item.url] = name
        }

        var written = 0
        for item in snapshot.items {
            guard let name = noteName[item.url] else { continue }
            var lines = ["---",
                         "url: \(ExportText.yaml(item.url))",
                         "theme: \(ExportText.yaml("[[\(ExportText.fileName(item.theme))]]"))",
                         "site: \(ExportText.yaml(item.site))",
                         "source: \(ExportText.yaml(item.source))"]
            if !item.sentTo.isEmpty { lines.append("sent_to: [\(item.sentTo.map(ExportText.yaml).joined(separator: ", "))]") }
            if let d = item.lastViewed { lines.append("saved: \(ExportText.day.string(from: d))") }
            lines += ["tags: [sift\(item.sentTo.isEmpty ? "" : ", sift/sent")]", "---", ""]
            if let image = item.imageURL { lines += ["![](\(image))", ""] }
            lines.append("[\(item.title.isEmpty ? item.url : item.title)](\(item.url))")
            lines.append("")
            if !item.use.isEmpty { lines += ["**Use:** \(item.use)", ""] }
            if !item.previewText.isEmpty { lines += ["> " + item.previewText.replacingOccurrences(of: "\n", with: " "), ""] }
            lines.append("Theme: [[\(ExportText.fileName(item.theme))]]")
            let file = linksDir.appending(path: "\(name).md")
            try write(lines.joined(separator: "\n"), to: file)
            written += 1
        }

        for theme in snapshot.themes {
            let items = snapshot.items(in: theme.name)
            var lines = ["---", "type: sift-theme", "description: \(ExportText.yaml(theme.summary))"]
            if !theme.destination.isEmpty { lines.append("destination: \(ExportText.yaml(theme.destination))") }
            lines += ["links: \(items.count)", "tags: [sift, sift/theme]", "---", ""]
            if !theme.summary.isEmpty { lines += [theme.summary, ""] }
            for item in items {
                if let n = noteName[item.url] {
                    lines.append("- [[\(n)]]" + (item.sentTo.isEmpty ? "" : " → \(item.sentTo.joined(separator: ", "))"))
                }
            }
            lines.append("")
            try write(lines.joined(separator: "\n"), to: themesDir.appending(path: "\(ExportText.fileName(theme.name)).md"))
        }

        var index = ["---", "type: sift-index", "exported: \(ExportText.day.string(from: snapshot.created))", "---", "",
                     "# Sift", "", "\(snapshot.items.count) links in \(snapshot.themes.count) themes.", ""]
        for theme in snapshot.themes.sorted(by: { $0.count > $1.count }) {
            index.append("- [[\(ExportText.fileName(theme.name))]] (\(theme.count))")
        }
        try write(index.joined(separator: "\n") + "\n", to: root.appending(path: "Sift.md"))

        return "Wrote \(written) link notes and \(snapshot.themes.count) theme notes to \(root.path(percentEncoded: false))."
    }

    /// Writes the note and keeps whatever the user wrote under "## Notes".
    private func write(_ body: String, to file: URL) throws {
        var text = body
        if let old = try? String(contentsOf: file, encoding: .utf8),
           let range = old.range(of: "\n\(Self.notesHeading)\n") {
            text += "\n" + old[range.lowerBound...].trimmingCharacters(in: .newlines) + "\n"
        } else {
            text += "\n\n\(Self.notesHeading)\n\n"
        }
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
