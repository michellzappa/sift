import Foundation

// MARK: - Adding a destination kind
//
// 1. Create Sift/Send/<Name>Sender.swift with a struct that conforms to
//    `Sender`.
// 2. Add one instance to `Senders.all` below.
// 3. Give Settings > Outputs a way to add a `Destination` of that kind.
// A sender gets one link at a time and the destination's own settings. It
// returns where the link landed (a URL or a file path), or throws.

/// A place links are sent to: a Starlings project, an Obsidian folder, a
/// Markdown file, the Reading List.
struct Destination: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// The sender kind: starlings, obsidian, markdown, reading-list.
    var kind: String
    /// Shown in menus: the project name, the folder name.
    var name: String
    /// Quieter text after the name: the workspace, the path.
    var detail: String = ""
    /// The sender's own settings, for example origin and project id.
    var config: [String: String] = [:]

    var symbol: String { Senders.sender(for: kind)?.symbol ?? "paperplane" }
}

/// One link, as a sender sees it.
struct SendItem: Sendable {
    let url: String
    let title: String
    let theme: String
    let note: String
    let summary: String
    /// The text Sift saved (page text or transcript), or "".
    let text: String
    let site: String
    let source: String
    let saved: Date?
}

/// Where a link was sent, and when.
struct SentRecord: Codable, Hashable, Sendable {
    let destination: String
    let date: Date
    /// Where it landed: a web address or a file path, when the sender knows.
    var link: String?
}

protocol Sender: Sendable {
    /// Matches `Destination.kind`.
    var kind: String { get }
    var label: String { get }
    var symbol: String { get }
    func send(_ item: SendItem, to destination: Destination) async throws -> String?
}

struct SendFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Senders {
    static let all: [any Sender] = [
        StarlingsSender(),
        ObsidianSender(),
        MarkdownSender(),
        ReadingListSender(),
    ]

    static func sender(for kind: String) -> (any Sender)? { all.first { $0.kind == kind } }
}
