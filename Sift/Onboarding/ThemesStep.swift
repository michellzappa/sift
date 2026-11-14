import SwiftUI

/// Discover Themes, with progress, then ThemeReview (shown by the guide
/// window). This is where the graph fills up.
struct ThemesStep: OnboardingStep {
    let id = "themes"
    let title = "Themes"
    let symbol = "circle.hexagongrid.circle"

    func status(_ model: AppModel) -> OnboardingStatus {
        if !model.themes.isEmpty { return .done("\(model.themes.count) themes") }
        if !model.hasReadableSource { return .blocked("Add a source first") }
        if !model.claudeReady { return .blocked("Set up Claude first") }
        if model.isDiscovering { return .available("Claude is reading your links") }
        return .available("Ready to read \(model.allSourcesCount) links")
    }

    var body: some View { Content() }

    private struct Content: View {
        @Environment(AppModel.self) private var model

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Claude reads all your links together and proposes 12 to 20 themes, each with a short description. You rename or untick them before anything changes. There are no folders to set up.")
                    .fixedSize(horizontal: false, vertical: true)

                if !model.hasReadableSource {
                    blocked("Sift has no links to read yet.", button: "Go to Sources", step: "sources")
                } else if !model.claudeReady {
                    blocked("Sift needs Claude Code or an API key to find themes.", button: "Go to Claude", step: "claude")
                } else if model.isDiscovering {
                    GroupBox {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Claude is reading \(model.allSourcesCount) links and grouping them.")
                                Text("You can close this window. Sift shows the themes when they are ready.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                } else if !model.themes.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Your graph is ready: \(model.themes.count) themes.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(model.projects.map(\.name).joined(separator: " · "))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Spacer()
                                Button("Discover Again") { Task { await model.discoverThemes() } }
                            }
                        }
                        .padding(6)
                    }
                } else {
                    HStack {
                        Button {
                            Task { await model.discoverThemes() }
                        } label: {
                            Label("Discover Themes", systemImage: "circle.hexagongrid.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Text("\(model.allSourcesCount) links").foregroundStyle(.secondary)
                    }
                }

                if let error = model.sortError, !model.isDiscovering {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        private func blocked(_ text: String, button: String, step: String) -> some View {
            HStack {
                Text(text).foregroundStyle(.secondary)
                Spacer()
                Button(button) { model.onboardingGo(to: step) }
            }
        }
    }
}
