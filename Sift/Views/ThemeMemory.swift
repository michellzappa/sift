import SwiftUI

/// A theme's header extras: where its links are sent, and what happened to
/// the theme over time. (No notes field: the owner removed it, 2026-11-14.)
struct ThemeMemory: View {
    @Environment(AppModel.self) private var model
    let theme: String
    @State private var showHistory = false

    var body: some View {
        let project = model.themes.first { $0.name == theme }
        VStack(alignment: .leading, spacing: 8) {
            if !model.destinations.isEmpty {
                HStack(spacing: 8) {
                    Picker("Sends to", selection: .init(get: { project?.sendTo ?? "" },
                                                        set: { model.setDefaultDestination($0.isEmpty ? nil : $0, forTheme: theme) })) {
                        Text("Nowhere yet").tag("")
                        ForEach(model.destinations) { d in Text(d.name).tag(d.id) }
                    }
                    .fixedSize()
                    if let d = model.destination(project?.sendTo) {
                        let unsent = model.tabs(in: theme).filter { tab in !model.sentRecords(tab.url).contains { $0.destination == d.id } }
                        if !unsent.isEmpty {
                            Button("Send \(unsent.count) to \(d.name)") { Task { await model.send(unsent, to: d) } }
                                .help("Sends every link in this theme that has not gone to \(d.name) yet.")
                        }
                    }
                }
                .controlSize(.small)
            }
            if let history = project?.history, !history.isEmpty {
                DisclosureGroup("History", isExpanded: $showHistory) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(history.reversed(), id: \.self) { Text($0) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
    }
}
