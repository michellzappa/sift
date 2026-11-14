import SwiftUI

/// A theme's memory at the top of its links: what Claude found it to be,
/// the user's own notes (Claude reads them when it sorts and rediscovers),
/// and what happened to the theme over time.
struct ThemeMemory: View {
    @Environment(AppModel.self) private var model
    let theme: String
    @State private var draft = ""
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
            TextField("Your notes on this theme: why it matters, what you want from it", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .font(.callout)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { model.setNotes(draft, for: theme) }
                .onChange(of: draft) { _, new in model.setNotes(new, for: theme) }
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
        .onAppear { draft = project?.notes ?? "" }
        .onChange(of: theme) { _, _ in draft = model.themes.first { $0.name == theme }?.notes ?? "" }
    }
}
