import Foundation

// MARK: - Adding an exporter
//
// 1. Create Sift/Export/<Name>Exporter.swift with a struct that conforms to
//    `Exporter`.
// 2. Add one instance to `Exporters.all` below.
// That is all. The Export menu, the folder or save panel and the result
// message come for free. An exporter only reads the snapshot it receives:
// it never sees app state, the network or the keychain.
// See CONTRIBUTING.md for the checklist.

/// One link, as exporters see it.
struct ExportItem: Sendable, Codable {
    let url: String
    let title: String
    /// The theme name, or "personal" for the personal bucket.
    let theme: String
    let use: String
    /// read, try, cite, contact, file or close. Empty when not set.
    let action: String
    let site: String
    let source: String
    let lastViewed: Date?
    let previewText: String
    let imageURL: String?
}

/// One theme, as exporters see it.
struct ExportTheme: Sendable, Codable {
    let name: String
    let summary: String
    let destination: String
    let count: Int
}

/// Everything an exporter gets. Links in "drop" and "unknown" and unsorted
/// links are left out.
struct ExportSnapshot: Sendable, Codable {
    let created: Date
    let themes: [ExportTheme]
    let items: [ExportItem]

    func items(in theme: String) -> [ExportItem] { items.filter { $0.theme == theme } }
}

enum ExportOutput: Sendable {
    var isFolder: Bool { if case .folder = self { return true } else { return false } }

    /// The user picks a folder; the exporter writes files inside it.
    case folder
    /// The user picks a file name with this extension.
    case file(extension: String)
    /// The exporter returns text; Sift copies it to the clipboard.
    case clipboard
}

protocol Exporter: Sendable {
    /// Stable id, used to remember the last folder. Lowercase, no spaces.
    var id: String { get }
    /// Menu title, for example "Obsidian Vault…".
    var name: String { get }
    /// One sentence for the menu tooltip and the README.
    var summary: String { get }
    var output: ExportOutput { get }

    /// Writes the snapshot. `destination` is the chosen folder or file, or
    /// nil for `.clipboard`. Returns text: a short result message for
    /// `.folder` and `.file`, the text to copy for `.clipboard`.
    func export(_ snapshot: ExportSnapshot, to destination: URL?) throws -> String
}

/// The registry. Order is menu order.
enum Exporters {
    static let all: [any Exporter] = [
        ObsidianExporter(),
        MarkdownExporter(),
        MarkdownClipboardExporter(),
        CSVExporter(),
        JSONExporter(),
    ]
}

/// Small helpers shared by exporters.
enum ExportText {
    /// A file name that works on macOS, Windows and in Obsidian links.
    static func fileName(_ s: String, limit: Int = 80) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]\n\r\t")
        let cleaned = s.unicodeScalars.map { bad.contains($0) ? " " : String($0) }.joined()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String((cleaned.isEmpty ? "untitled" : cleaned).prefix(limit))
    }

    /// A YAML string value with quotes escaped.
    static func yaml(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ") + "\""
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
