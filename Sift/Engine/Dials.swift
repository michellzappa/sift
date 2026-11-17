import Foundation

/// Theme dials (owner, 2026-11-17: "theme dials"; "keeping it simple").
/// Each theme says how it takes part in Today:
/// - Stay: as it is. Only the feeds you follow.
/// - Lean In: more of what you already like there. The theme's lift in
///   Today doubles, and Sift tries up to 2 creators you already save from in
///   that theme but do not follow.
/// - Explore: one step out. Sift tries up to 3 sources from Next Door, the
///   directory and Farther for that theme.
/// A tried source is not a follow. Its items come into Today marked "Trying
/// for <theme>" (at most `picks` per theme), it stays out of the Feeds
/// list, and after `Trials.days` it goes unless you follow it. Keeping one
/// of its items gives it another two weeks. Sift never follows for you.
enum ThemeDial: String, CaseIterable, Codable, Sendable, Identifiable {
    case stay, leanIn, explore
    var id: String { rawValue }

    var title: String {
        switch self {
        case .stay: "Stay"
        case .leanIn: "Lean In"
        case .explore: "Explore"
        }
    }

    var help: String {
        switch self {
        case .stay: "Only the feeds you follow."
        case .leanIn: "Twice the theme's lift in Today, and Sift tries up to 2 creators you already save from here."
        case .explore: "Sift tries up to 3 sources one step out: Next Door, the directory and Farther."
        }
    }

    /// Tried sources per theme.
    var trials: Int {
        switch self {
        case .stay: 0
        case .leanIn: 2
        case .explore: 3
        }
    }

    /// Tried-source items per theme in Today.
    var picks: Int { trials }

    /// The factor on the theme's lift in Today.
    var lift: Double { self == .leanIn ? 2 : 1 }

    init(_ raw: String?) { self = raw.flatMap(ThemeDial.init(rawValue:)) ?? .stay }
}

enum Trials {
    static let days: Double = 14
    /// Tried sources across all themes.
    static let maxTotal = 12

    /// A source Sift could try for a theme.
    struct Candidate: Sendable {
        var id: String
        var name: String
        var input: String
        /// Where it came from, shown on its items.
        var source: String
    }
}
