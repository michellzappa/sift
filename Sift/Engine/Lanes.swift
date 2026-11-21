import Foundation

/// Custom lanes (owner, 2026-11-17, roadmap 2: "keeping it simple"). Bluesky's
/// custom feeds and X lists, made local: a lane is a saved rule over the
/// items of your feeds from the last `days` days, newest first. A rule is any
/// of: words (an item matches when it has one of them), a feed folder, a
/// theme (by meaning or by words) and a type (Scan, Watch, Read). All parts
/// you set must match. A lane ends: it holds at most `limit` items.
struct Lane: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    /// Words or phrases, comma separated; an item matches one of them.
    var words: String = ""
    var folder: String? = nil
    var theme: String? = nil
    /// `ReadingMode` raw value.
    var mode: String? = nil

    var terms: [String] {
        words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    /// "agents, evals · in AI · Read"
    var rule: String {
        var parts: [String] = []
        if !terms.isEmpty { parts.append(terms.joined(separator: ", ")) }
        if let folder { parts.append("folder \(folder)") }
        if let theme { parts.append("in \(theme)") }
        if let mode, let m = ReadingMode(rawValue: mode) { parts.append(m.title) }
        return parts.isEmpty ? "every item" : parts.joined(separator: " · ")
    }
}

enum Lanes {
    static let days: Double = 14
    static let limit = 60

    /// True when the text has the term as a word or phrase, not inside a
    /// longer word ("ai" does not match "said").
    static func has(_ text: String, _ term: String) -> Bool {
        let pattern = "(^|[^\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "($|[^\\p{L}\\p{N}])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The lane's items: newest first, unseen before seen, at most `limit`.
    static func items(_ lane: Lane, picks: [TodayPick], feeds: [String: Feed],
                      mode: (TodayPick) -> ReadingMode, theme: (TodayPick) -> String?, isSeen: (String) -> Bool,
                      now: Date = Date()) -> [TodayPick] {
        let since = now.addingTimeInterval(-days * 86_400)
        let terms = lane.terms
        let out = picks.filter { p in
            guard (p.date ?? now) >= since else { return false }
            if let folder = lane.folder, feeds[p.feedID]?.category != folder { return false }
            if let m = lane.mode, mode(p).rawValue != m { return false }
            if let t = lane.theme, theme(p) != t { return false }
            if !terms.isEmpty {
                let text = p.title + " " + p.summary + " " + String((p.content ?? "").prefix(3000))
                if !terms.contains(where: { has(text, $0) }) { return false }
            }
            return true
        }
        let unseen = out.filter { !isSeen($0.url) }, seen = out.filter { isSeen($0.url) }
        return Array((unseen + seen).prefix(limit))
    }
}
