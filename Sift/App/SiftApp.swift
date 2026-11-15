import SwiftUI
import UniformTypeIdentifiers

@main
struct SiftApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var delegate: SiftAppDelegate

    var body: some Scene {
        WindowGroup("Sift") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reload Tabs") { model.reload() }
                    .keyboardShortcut("r")
                Button("Import Links File…") { model.importLinksFile() }
                    .keyboardShortcut("i")
                Button("Import Sorted CSV…") { importCSV() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Menu("Export") {
                    ForEach(Exporters.all, id: \.id) { exporter in
                        Button(exporter.name) { model.runExport(exporter) }
                            .help(exporter.summary)
                    }
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await UpdateChecker.shared.checkFromMenu() } }
            }
            CommandGroup(replacing: .help) {
                SetupGuideCommand(model: model)
            }
        }

        // The Setup Guide: one window, opened on first run, by Help >
        // Setup Guide, and from the main window's empty states.
        Window("Setup Guide", id: Onboarding.windowID) {
            OnboardingView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    @MainActor
    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try model.importCSV(from: url)
            model.sortError = nil
            NSSound(named: "Glass")?.play()
            _ = count
        } catch {
            model.sortError = error.localizedDescription
        }
    }
}

/// Makes sure Sift shows its main window after launch. A launch from a
/// script (`open -n`, the screenshot script) can come up with only the menu
/// bar; then Sift opens a window the way File > New Window does.
final class SiftAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let hasMain = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && $0.identifier?.rawValue != "com_apple_SwiftUI_Settings_window" }
            guard !hasMain else { return }
            let items = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
            if let new = items.first(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }), let action = new.action {
                NSApp.sendAction(action, to: new.target, from: new)
            }
            NSApp.activate()
        }
    }
}
