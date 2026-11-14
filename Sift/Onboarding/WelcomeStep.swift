import SwiftUI

/// What Sift is, and that the data stays on this Mac.
struct WelcomeStep: OnboardingStep {
    let id = "welcome"
    let title = "Welcome to Sift"
    let symbol = "circle.hexagongrid"
    var isOptional: Bool { false }

    func status(_ model: AppModel) -> OnboardingStatus { .done("No account needed") }

    var body: some View { Content() }

    private struct Content: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sift reads the links you already save: open tabs on your iPhone and other devices, your Reading List, Instagram saves, YouTube playlists and exports from read-later apps. It finds the themes you keep coming back to and draws them as a graph.")
                    .fixedSize(horizontal: false, vertical: true)
                OnboardingNote(symbol: "lock", title: "Your data stays on this Mac",
                               text: "Sift has no account and no server. It reads your sources and never changes them.")
                OnboardingNote(symbol: "doc.text", title: "Plain files",
                               text: "Page text is Markdown and your themes are JSON, in ~/Library/Application Support/Sift. You can open every file without Sift.")
                OnboardingNote(symbol: "sparkles", title: "Your own Claude",
                               text: "Claude names your themes through your Claude Code login or your API key. It sees titles, URLs and short previews. It does not see whole pages.")
                Text("You can skip any step and come back to it from Help > Setup Guide.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
