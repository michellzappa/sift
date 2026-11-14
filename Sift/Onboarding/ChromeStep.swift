import AppKit
import SwiftUI

/// Chrome's open tabs as a source, through a small extension and the
/// sift-chrome helper inside Sift.app.
struct ChromeStep: OnboardingStep {
    let id = "chrome"
    let title = "Chrome"
    let symbol = "globe"

    func status(_ model: AppModel) -> OnboardingStatus {
        if !model.chromeProfiles.isEmpty { return .done("\(model.chromeTabCount) tabs from Chrome") }
        if ChromeHelper.installedBrowsers.isEmpty { return .available("No Chrome-based browser on this Mac") }
        if ChromeHelper.isInstalled { return .available("Helper installed. Add the extension next.") }
        return .available("Not set up")
    }

    var body: some View { Content() }

    private struct Content: View {
        @Environment(AppModel.self) private var model

        private let steps = [
            "Click Install Chrome Helper. Sift sets up Chrome and other Chromium browsers it finds, shows the extension folder in Finder and opens the extensions page.",
            "On chrome://extensions, turn on Developer mode (top right).",
            "Drag the extension folder onto the page, or click Load unpacked and choose it. In that window, Command-Shift-G lets you paste the folder path.",
            "Come back here. Your Chrome tabs show up within a minute.",
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("If you keep tabs open in Chrome, Sift can read them too, from every window and every profile where you add the extension. When you mark a Chrome tab to close in Sift, the extension closes it. The extension reads only the address and title of each tab and sends them to Sift on this Mac. It does not use the internet.")
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 18, alignment: .trailing)
                                    Text(step).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        ChromeHelperButtons()
                        if let message = model.chromeHelperMessage {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }

                Text("Add the extension in each Chrome profile you want in Sift. Each profile shows as its own source.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The snapshot may have arrived while the user was in Chrome.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if model.chromeProfiles.isEmpty, ChromeReader.latestChange() != nil { model.reload() }
            }
        }
    }
}
