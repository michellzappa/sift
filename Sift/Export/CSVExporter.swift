import Foundation

/// A CSV that File > Import Sorted CSV reads back, so a sort can move between
/// Macs or go through a spreadsheet and come back.
struct CSVExporter: Exporter {
    let id = "csv"
    let name = "CSV File…"
    let summary = "One row per link. File > Import Sorted CSV reads it back."
    let output = ExportOutput.file(extension: "csv")

    func export(_ snapshot: ExportSnapshot, to destination: URL?) throws -> String {
        var rows = [["project", "title", "url", "possible use", "sent to", "site", "last viewed"]]
        for item in snapshot.items {
            rows.append([item.theme, item.title, item.url, item.use, item.sentTo.joined(separator: "; "), item.site,
                         item.lastViewed.map { ExportText.day.string(from: $0) } ?? ""])
        }
        let text = rows.map { $0.map(Self.field).joined(separator: ",") }.joined(separator: "\n") + "\n"
        guard let destination else { return text }
        try text.write(to: destination, atomically: true, encoding: .utf8)
        return "Wrote \(snapshot.items.count) rows to \(destination.lastPathComponent)."
    }

    private static func field(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}
