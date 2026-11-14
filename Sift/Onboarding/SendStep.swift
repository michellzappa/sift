import SwiftUI

/// Optional: where finished links go. More kinds live in Settings > Outputs.
struct SendStep: OnboardingStep {
    let id = "send"
    let title = "Send"
    let symbol = "paperplane"

    func status(_ model: AppModel) -> OnboardingStatus {
        let n = model.destinations.count
        return n == 0 ? .available("Optional") : .done("\(n) \(n == 1 ? "destination" : "destinations")")
    }

    var body: some View { Content() }

    private struct Content: View {
        @Environment(AppModel.self) private var model
        @State private var connecting = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("A link stays in Sift until you send it where you will use it. You can skip this and add places later in Settings > Outputs, which also has a Markdown file and the Reading List.")
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusRow(icon: "person.2", name: "Starlings",
                                  status: "Saves each link to your Links in Starlings Docs. Sift signs in as you.") {
                            Button("Connect…") { connecting = true }
                        }
                        Divider()
                        StatusRow(icon: "folder", name: "Obsidian",
                                  status: "Writes one note per link into a folder in your vault.") {
                            Button("Add Folder…") { model.addObsidianDestination() }
                        }
                    }
                    .padding(6)
                }

                if !model.destinations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your destinations").font(.headline)
                        ForEach(model.destinations) { d in
                            Label { Text(d.name) + Text(d.detail.isEmpty ? "" : "  \(d.detail)").foregroundStyle(.secondary) } icon: { d.image }
                                .lineLimit(1)
                        }
                    }
                }
            }
            .sheet(isPresented: $connecting) { StarlingsConnect().environment(model) }
        }
    }
}
