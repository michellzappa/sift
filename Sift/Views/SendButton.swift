import SwiftUI

/// Sends a link. A click sends to the theme's destination (when the theme
/// has one); the menu lists every destination. Sending is immediate. A sent
/// link shows a filled plane and can open where it landed.
struct SendButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let tab: SafariTab
    /// Icon only, for rows.
    var compact = false

    var body: some View {
        let records = model.sentRecords(tab.url)
        let fallback = model.defaultDestination(for: tab)
        let lastName = records.last.flatMap { model.destination($0.destination)?.name }
        Menu {
            menuItems(records)
        } label: {
            if model.sending.contains(tab.url) {
                ProgressView().controlSize(.mini)
            } else if compact {
                Image(systemName: records.isEmpty ? "paperplane" : "paperplane.fill")
            } else {
                Label(lastName.map { "Sent to \($0)" } ?? fallback.map { "Send to \($0.name)" } ?? "Send",
                      systemImage: records.isEmpty ? "paperplane" : "paperplane.fill")
            }
        } primaryAction: {
            if let d = fallback, !records.contains(where: { $0.destination == d.id }) {
                Task { await model.send(tab, to: d) }
            } else if model.destinations.isEmpty {
                openSettings()
            }
        }
        .help(help(records, fallback))
    }

    @ViewBuilder
    private func menuItems(_ records: [SentRecord]) -> some View {
        ForEach(model.destinations) { d in
            let sent = records.contains { $0.destination == d.id }
            Button { Task { await model.send(tab, to: d) } } label: {
                Label { Text(d.detail.isEmpty ? d.name : "\(d.name) · \(d.detail)") } icon: { sent ? Image(systemName: "checkmark") : d.image }
            }
            .disabled(sent)
        }
        if !records.isEmpty {
            Divider()
            ForEach(records, id: \.self) { r in
                if let link = r.link, let d = model.destination(r.destination) {
                    Button("Open in \(d.name)") { open(link) }
                }
            }
        }
        Divider()
        Button("Add Destination…") { openSettings() }
    }

    private func open(_ link: String) {
        if link.hasPrefix("http"), let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        } else if link.hasPrefix("/") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: link)])
        }
    }

    private func help(_ records: [SentRecord], _ fallback: Destination?) -> String {
        if let r = records.last, let d = model.destination(r.destination) {
            return "Sent to \(d.name) on \(r.date.formatted(date: .abbreviated, time: .shortened))."
        }
        if let fallback { return "Click to send to \(fallback.name). The menu lists every destination." }
        return model.destinations.isEmpty ? "Add a destination in Settings > Outputs." : "Choose where to send this link."
    }
}
