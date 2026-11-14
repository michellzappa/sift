import SwiftUI
import UniformTypeIdentifiers

@main
struct SiftApp: App {
    @State private var model = AppModel()

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
