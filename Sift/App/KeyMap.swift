import Foundation

/// Single-key shortcuts in the style of Google Reader. `KeyMap.bindings` is
/// the one list: `KeyRouter` dispatches from it and the shortcuts sheet (?)
/// shows it. Keys work in the main window when no text field has focus;
/// ⌘, ⌃ and ⌥ combinations stay with the menus.
enum KeyAction: Hashable, Sendable {
    // In a list
    case next, previous, open, original, keep, toggleSeen, markAllSeen, copyLink, follow, send, trail
    // Anywhere in the main window
    case go(SidebarItem), nextSource, previousSource, refresh, search, followSheet, help
    /// Scan, Watch, Read; nil = All.
    case mode(ReadingMode?)
}

struct KeyBinding: Identifiable, Sendable {
    /// What the user types: "j", "A" (shift-a), "g t" (g, then t).
    var keys: String
    var action: KeyAction
    var title: String
    var group: String
    var id: String { keys }
}

enum KeyMap {
    static let bindings: [KeyBinding] = [
        // Moving through a list
        .init(keys: "j", action: .next, title: "Next item", group: "List"),
        .init(keys: "k", action: .previous, title: "Previous item", group: "List"),
        .init(keys: "n", action: .next, title: "Next item", group: "List"),
        .init(keys: "p", action: .previous, title: "Previous item", group: "List"),
        .init(keys: "o", action: .open, title: "Open or close the page beside the list", group: "List"),
        .init(keys: "↩", action: .open, title: "Open or close the page beside the list", group: "List"),
        .init(keys: "v", action: .original, title: "Open the original in your browser", group: "List"),
        // Acting on the item
        .init(keys: "s", action: .keep, title: "Keep (Today and feeds)", group: "Item"),
        .init(keys: "m", action: .toggleSeen, title: "Mark as seen or unseen", group: "Item"),
        .init(keys: "A", action: .markAllSeen, title: "Mark every item in the list as seen", group: "Item"),
        .init(keys: "c", action: .copyLink, title: "Copy the link", group: "Item"),
        .init(keys: "f", action: .follow, title: "Follow the item's site", group: "Item"),
        .init(keys: "t", action: .trail, title: "More like this: open a trail from the item", group: "Item"),
        .init(keys: "e", action: .send, title: "Send to the theme's destination", group: "Item"),
        // Going places
        .init(keys: "g t", action: .go(.today), title: "Go to Today", group: "Go"),
        .init(keys: "g a", action: .go(.overview), title: "Go to all items (Overview)", group: "Go"),
        .init(keys: "g u", action: .go(.unsorted), title: "Go to Unsorted", group: "Go"),
        .init(keys: "g k", action: .go(.source(TodayStore.keptSourceID)), title: "Go to Kept from Today", group: "Go"),
        .init(keys: "g r", action: .go(.archive), title: "Go to Closed or Removed", group: "Go"),
        .init(keys: "g x", action: .go(.transcripts), title: "Go to Transcripts", group: "Go"),
        .init(keys: "g d", action: .go(.duplicates), title: "Go to Duplicates", group: "Go"),
        .init(keys: "J", action: .nextSource, title: "Next feed or theme in the sidebar", group: "Go"),
        .init(keys: "K", action: .previousSource, title: "Previous feed or theme in the sidebar", group: "Go"),
        // Modes
        .init(keys: "0", action: .mode(nil), title: "All items", group: "Mode"),
        .init(keys: "1", action: .mode(.scan), title: "Scan: headlines and posts", group: "Mode"),
        .init(keys: "2", action: .mode(.watch), title: "Watch: videos as cards", group: "Mode"),
        .init(keys: "3", action: .mode(.read), title: "Read: long texts", group: "Mode"),
        // The app
        .init(keys: "r", action: .refresh, title: "Refresh: reload sources and check feeds", group: "App"),
        .init(keys: "/", action: .search, title: "Search", group: "App"),
        .init(keys: "a", action: .followSheet, title: "Follow a site, a feed or an account", group: "App"),
        .init(keys: "?", action: .help, title: "Show these shortcuts", group: "App"),
    ]

    static let groups = ["List", "Item", "Go", "Mode", "App"]

    /// The binding for a typed sequence ("j", "g t"), if any.
    static func action(for keys: String) -> KeyAction? {
        bindings.first { $0.keys == keys }?.action
    }

    /// True when `key` starts a two-key sequence ("g").
    static func isPrefix(_ key: String) -> Bool {
        bindings.contains { $0.keys.hasPrefix(key + " ") }
    }
}
