import AppKit
import SwiftUI

/// Which Claude sorts the links: the Claude Code login, else an API key.
struct ClaudeStep: OnboardingStep {
    let id = "claude"
    let title = "Claude"
    let symbol = "sparkles"

    func status(_ model: AppModel) -> OnboardingStatus {
        guard model.claudeReady else { return .available("Not set up yet") }
        return .done(model.state.backend == .claudeCode ? "Uses Claude Code" : "Uses your API key")
    }

    var body: some View { Content() }

    private struct Content: View {
        @Environment(AppModel.self) private var model
        @State private var key = ""
        @State private var hasKey = Keychain.readKey() != nil

        var body: some View {
            let claudeCode = ClaudeCodeRunner.executable
            VStack(alignment: .leading, spacing: 16) {
                Text("Claude names your themes and sorts new links into them. Sift uses your own Claude, so you do not need a Sift account.")
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if let claudeCode {
                            StatusRow(icon: "checkmark.circle", name: "Claude Code is installed",
                                      status: (claudeCode.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath) {
                                if model.state.backend != .claudeCode {
                                    Button("Use Claude Code") { model.state.backend = .claudeCode }
                                } else {
                                    Label("In use", systemImage: "checkmark").foregroundStyle(.green)
                                }
                            }
                            Text("Sift runs it with your Claude Code login, so you do not need an API key. If Claude Code is not signed in, Discover Themes says so: run claude once in Terminal to sign in.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 34)
                        } else {
                            StatusRow(icon: "questionmark.circle", name: "Claude Code was not found",
                                      status: "Sift looks in ~/.local/bin and Homebrew.", warning: true) {
                                Button("Get Claude Code") {
                                    if let url = URL(string: "https://claude.com/claude-code") { NSWorkspace.shared.open(url) }
                                }
                            }
                            Text("Install Claude Code and sign in, then come back to this step. Or use an API key below.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 34)
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anthropic API key").font(.headline)
                        HStack {
                            SecureField("API key", text: $key, prompt: Text(hasKey ? "Saved in the keychain" : "sk-ant-…"))
                                .onSubmit(save)
                            Button("Save Key", action: save).disabled(key.isEmpty)
                            if hasKey {
                                Button("Remove", role: .destructive) {
                                    Keychain.saveKey("")
                                    hasKey = false
                                    if claudeCode != nil { model.state.backend = .claudeCode }
                                }
                            }
                        }
                        Text(hasKey && model.state.backend == .api
                             ? "Sift uses this key. Anthropic bills your API account."
                             : "The key stays in your login keychain. Anthropic bills your API account.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(6)
                }

                OnboardingNote(symbol: "arrow.up.message", title: "What Sift sends to Claude",
                               text: "The title, URL and a short preview of each link, and your theme names. Sift never sends whole pages. Errands, like orders, carts and account pages, never go to Claude.")
            }
        }

        private func save() {
            guard !key.isEmpty else { return }
            Keychain.saveKey(key)
            key = ""
            hasKey = Keychain.readKey() != nil
            if hasKey { model.state.backend = .api }
        }
    }
}
