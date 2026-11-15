import AppKit

/// Reads key presses in the main window and turns them into `KeyAction`s
/// (KeyMap.swift). A local NSEvent monitor, so keys work wherever the focus
/// is in the window, except in a text field, a sheet or with ⌘ ⌃ ⌥ held.
/// The visible list registers `listHandler`; global actions go to the model.
@MainActor
final class KeyRouter {
    static let shared = KeyRouter()

    weak var model: AppModel?
    /// Set by the visible list (TabList, OfferedList). Returns true when it
    /// used the action.
    private(set) var listHandler: ((KeyAction) -> Bool)?
    private var listOwner: UUID?

    /// A list takes the list keys while it is on screen. The token makes
    /// sure an old list leaving does not remove a new list's handler.
    func register(_ owner: UUID, _ handler: @escaping (KeyAction) -> Bool) {
        listOwner = owner
        listHandler = handler
    }

    func unregister(_ owner: UUID) {
        guard listOwner == owner else { return }
        listOwner = nil
        listHandler = nil
    }

    private var monitor: Any?
    private var prefix: (key: String, at: Date)?

    func install(_ model: AppModel) {
        self.model = model
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { KeyRouter.shared.handle(event) } ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = NSApp.keyWindow, window.attachedSheet == nil, isMainWindow(window) else { return false }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return false }
        // Typing in a text field, the search field or a note: keys are text.
        if window.firstResponder is NSText || window.firstResponder is NSTextView { return false }
        guard var key = event.charactersIgnoringModifiers, !key.isEmpty else { return false }
        if event.keyCode == 36 { key = "↩" }
        if event.modifierFlags.contains(.shift), key.count == 1, key.first?.isLetter == true { key = key.uppercased() }

        var sequence = key
        if let p = prefix, Date().timeIntervalSince(p.at) < 1.5 {
            sequence = p.key + " " + key
            prefix = nil
        } else if KeyMap.isPrefix(key) {
            prefix = (key, Date())
            return true
        }
        guard let action = KeyMap.action(for: sequence) else { return false }
        return perform(action)
    }

    private func perform(_ action: KeyAction) -> Bool {
        guard let model else { return false }
        switch action {
        case .go(let item):
            model.navigationRequest = item
        case .nextSource:
            model.stepSidebar(1)
        case .previousSource:
            model.stepSidebar(-1)
        case .refresh:
            model.reload()
            Task { await model.fetchFeeds(force: true) }
        case .search:
            focusSearchField()
        case .followSheet:
            model.showAddFeed = true
        case .help:
            model.showShortcuts.toggle()
        default:
            return listHandler?(action) ?? false
        }
        return true
    }

    /// The main window, not Settings, the Setup Guide or Version History.
    private func isMainWindow(_ window: NSWindow) -> Bool {
        let id = window.identifier?.rawValue ?? ""
        return window.canBecomeMain && !id.contains("Settings") && !id.contains("setup-guide") && !id.contains("version-history")
    }

    /// Puts the cursor in the toolbar's search field.
    private func focusSearchField() {
        guard let window = NSApp.keyWindow, let toolbar = window.toolbar else { return }
        for item in toolbar.items {
            if let search = item as? NSSearchToolbarItem {
                window.makeFirstResponder(search.searchField)
                return
            }
            if let field = item.view as? NSSearchField {
                window.makeFirstResponder(field)
                return
            }
        }
    }
}
