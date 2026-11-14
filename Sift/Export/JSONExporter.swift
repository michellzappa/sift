import Foundation

/// The whole snapshot as JSON, for scripts and other tools.
struct JSONExporter: Exporter {
    let id = "json"
    let name = "JSON File…"
    let summary = "The full snapshot (themes and links) as JSON, for scripts and other tools."
    let output = ExportOutput.file(extension: "json")

    func export(_ snapshot: ExportSnapshot, to destination: URL?) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        guard let destination else { return String(decoding: data, as: UTF8.self) }
        try data.write(to: destination, options: .atomic)
        return "Wrote \(snapshot.items.count) links to \(destination.lastPathComponent)."
    }
}
