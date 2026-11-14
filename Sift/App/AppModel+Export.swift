import AppKit
import Foundation

extension AppModel {
    // MARK: Exporters

    /// What every exporter receives: sorted links in themes and the personal
    /// bucket, never drop, unknown or unsorted ones.
    func exportSnapshot() -> ExportSnapshot {
        let source = isReadingList ? "reading-list" : isInstagram ? InstagramReader.sourceID : (devices.first { $0.id == state.deviceID }?.name ?? "tabs")
        let items: [ExportItem] = tabs.compactMap { tab in
            guard let a = state.assignments[tab.url], a.project != Project.drop, a.project != Project.unknown,
                  a.project != Project.errands else { return nil }
            let p = previews[tab.url]
            let usable = p?.failed == false ? p : nil
            let title = tab.hasUsefulTitle ? tab.title : (usable.map { $0.site == "x.com" ? "\($0.title) on X" : $0.title } ?? tab.url)
            return ExportItem(url: tab.url, title: title, theme: a.project, use: a.use,
                              sentTo: sentRecords(tab.url).compactMap { destination($0.destination)?.name },
                              site: tab.host, source: source, lastViewed: tab.lastViewed,
                              previewText: usable?.text ?? "", imageURL: usable?.imageURL)
        }
        var themeList = projects.map { theme in
            ExportTheme(name: theme.name, summary: theme.summary, destination: theme.destination,
                        count: items.filter { $0.theme == theme.name }.count)
        }
        let personal = items.filter { $0.theme == Project.personal }.count
        if personal > 0 { themeList.append(ExportTheme(name: Project.personal, summary: "Personal life, not a theme.", destination: "", count: personal)) }
        return ExportSnapshot(created: .now, themes: themeList.filter { $0.count > 0 }, items: items)
    }

    /// Asks for a folder or file when the exporter needs one, runs it, and
    /// shows its message.
    func runExport(_ exporter: any Exporter) {
        let snapshot = exportSnapshot()
        guard !snapshot.items.isEmpty else { exportMessage = "Nothing to export yet. Sort some tabs first."; return }
        var target: URL?
        switch exporter.output {
        case .clipboard:
            break
        case .folder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export Here"
            panel.message = "\(exporter.name.replacingOccurrences(of: "…", with: "")): choose a folder"
            if let last = state.exportTargets[exporter.id] { panel.directoryURL = URL(filePath: last) }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            target = url
        case .file(let ext):
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Sift \(ExportText.day.string(from: .now)).\(ext)"
            panel.canCreateDirectories = true
            if let last = state.exportTargets[exporter.id] { panel.directoryURL = URL(filePath: last) }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            target = url
        }
        do {
            let result = try exporter.export(snapshot, to: target)
            if case .clipboard = exporter.output {
                copy(result)
                exportMessage = "Copied \(snapshot.items.count) links."
            } else {
                exportMessage = result
                if let t = target {
                    let remember = (exporter.output.isFolder ? t : t.deletingLastPathComponent()).path(percentEncoded: false)
                    state.exportTargets[exporter.id] = remember
                }
            }
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: Import and export

    /// Imports a CSV with the columns project, title, url, possible use.
    /// Imported rows count as hand-sorted.
    func importCSV(from url: URL) throws -> Int {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = CSV.parse(text)
        guard let header = rows.first?.map({ $0.lowercased() }),
              let p = header.firstIndex(of: "project"), let u = header.firstIndex(of: "url")
        else { throw Sorter.Failure(message: "The CSV needs a header row with project and url columns.") }
        let useIndex = header.firstIndex(where: { $0.contains("use") })
        var count = 0
        for row in rows.dropFirst() where row.count > max(p, u) {
            let project = row[p].trimmingCharacters(in: .whitespaces).lowercased()
            guard !project.isEmpty else { continue }
            if !Project.buckets.contains(project), !projects.contains(where: { $0.name == project }) {
                addTheme(name: project, summary: "")
            }
            let use = useIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
            state.assignments[row[u]] = Assignment(project: project, use: use, manual: true, action: nil)
            count += 1
        }
        return count
    }

    func markdown(for project: String) -> String {
        var lines = ["## \(project)", ""]
        for tab in tabs(in: project) {
            let use = state.assignments[tab.url]?.use ?? ""
            lines.append("- [\(tab.displayTitle.prefix(100))](\(tab.url))" + (use.isEmpty ? "" : ": \(use)"))
        }
        return lines.joined(separator: "\n") + "\n"
    }


    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Minimal RFC 4180 CSV parser: quoted fields, doubled quotes, CRLF.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character?
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = chars.next() {
                        if n == "\"" { field.append("\"") } else { quoted = false; pending = n }
                    } else { quoted = false }
                } else { field.append(c) }
                continue
            }
            switch c {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
