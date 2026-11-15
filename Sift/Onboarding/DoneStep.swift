import SwiftUI

/// Three things worth knowing on day one.
struct DoneStep: OnboardingStep {
    let id = "done"
    let title = "You're Set"
    let symbol = "checkmark.seal"

    func status(_ model: AppModel) -> OnboardingStatus { .done("") }

    var body: some View { Content() }

    private struct Content: View {
        @State private var mcpMessage: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingNote(symbol: "circle.hexagongrid", title: "The graph",
                               text: "Overview shows each theme as a hub with its links around it. Click a theme to zoom in. Esc zooms back out.")
                OnboardingNote(symbol: "list.bullet", title: "The list",
                               text: "Click a theme in the sidebar to see its links. ↑ and ↓ move through them, and Space opens the page next to the list.")
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingNote(symbol: "sparkles", title: "Claude can read your library",
                                   text: "Add Sift to Claude Code, and Claude can search your links, saved pages and transcripts.")
                    HStack {
                        Button("Add to Claude Code") { Task { mcpMessage = await MCPSetup.addToClaudeCode() } }
                            .disabled(ClaudeCodeRunner.executable == nil)
                        if let mcpMessage { Text(mcpMessage).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.leading, 36)
                }
                OnboardingNote(symbol: "hand.raised", title: "Anonymous usage counts",
                               text: "Once a week Sift sends a small report with no links, titles or names in it, so we can see which Macs and features are in use. Turn it off in Settings > Privacy.")
                Text("Help > Setup Guide opens this guide again.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
