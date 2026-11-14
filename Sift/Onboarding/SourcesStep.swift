import AppKit
import SwiftUI

/// Where links come from. Full Disk Access lives here: Sift checks again
/// each time the user comes back from System Settings.
struct SourcesStep: OnboardingStep {
    let id = "sources"
    let title = "Sources"
    let symbol = "tray.and.arrow.down"

    func status(_ model: AppModel) -> OnboardingStatus {
        if model.hasReadableSource { return .done("\(model.allSourcesCount) links ready") }
        if model.needsDiskAccess { return .available("Full Disk Access is off") }
        return .available("No links yet")
    }

    var body: some View { Content() }

    private struct Content: View {
        @Environment(AppModel.self) private var model

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose where your links come from. Sift only reads them. Sift needs at least one source with links before it can find your themes.")
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusRow(icon: "safari", name: "Safari tabs", status: model.tabsStatus, warning: model.loadError != nil) {
                            if model.needsDiskAccess {
                                Button("Open Full Disk Access") { AppModel.openFullDiskAccessSettings() }
                                    .buttonStyle(.borderedProminent)
                            }
                            if model.loadError != nil {
                                Button("Check Again") { model.reload() }
                            }
                        }
                        if model.needsDiskAccess {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("In System Settings, click + under the Full Disk Access list, choose Sift in Applications and turn it on. Then come back here: Sift checks again by itself.")
                                Text("If Safari still shows as locked, Sift has to restart before macOS lets it in.")
                                Button("Quit and Reopen Sift") { model.relaunch(resumingAt: "sources") }
                                    .buttonStyle(.link)
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 34)
                        }
                        Divider()
                        StatusRow(icon: "eyeglasses", name: "Safari Reading List", status: model.readingListStatus, warning: model.needsDiskAccess)
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusRow(icon: "camera", name: "Instagram Saved", status: model.instagramStatus,
                                  warning: model.state.instagramExportPath != nil && model.instagramError != nil) {
                            Button("Choose Export…") { model.chooseInstagramExport() }
                        }
                        hint(model.instagramError ?? "In Instagram's Accounts Center, open Download your information and ask for JSON. Choose the zip when it arrives.")
                        Divider()
                        StatusRow(icon: "play.rectangle", name: "YouTube playlists", status: model.youtubeStatus) {
                            Button("Import Takeout…") { model.importLinksFile() }
                        }
                        hint("Export \"YouTube and YouTube Music\" from Google Takeout, then choose the zip. Watch Later comes first.")
                        Divider()
                        StatusRow(icon: "doc.text", name: "Other exports", status: model.importStatus) {
                            Button("Import File…") { model.importLinksFile() }
                        }
                        hint(model.importError ?? "Instapaper, Pocket, Readwise, Raindrop, Pinboard, or a bookmarks file from any browser.")
                        Divider()
                        StatusRow(icon: "at", name: "X bookmarks", status: model.xStatus) {
                            SettingsLink { Text("Set Up in Settings…") }
                        }
                        hint("X bookmarks need your own X developer app, which X bills per post read. Sift shows X posts without it.")
                    }
                    .padding(6)
                }
            }
            // Coming back from System Settings: check Full Disk Access again.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if model.loadError != nil { model.reload() }
            }
        }

        private func hint(_ text: String) -> some View {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 34)
        }
    }
}
