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
                Button("Import Sorted CSV…") { importCSV() }
                    .keyboardShortcut("i")
                Divider()
                Button("Copy All as Markdown") { model.copy(model.allMarkdown) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }

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
