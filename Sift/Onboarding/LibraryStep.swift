import AppKit
import SwiftUI

/// What Sift saves on this Mac, with the same switches as Settings > Library.
struct LibraryStep: OnboardingStep {
    let id = "library"
    let title = "Library"
    let symbol = "books.vertical"

    func status(_ model: AppModel) -> OnboardingStatus {
        model.state.autoCapture ? .done("Saves page text") : .available("Page text is off")
    }

    var body: some View { Content() }

    private struct Content: View {
        @Environment(AppModel.self) private var model

        var body: some View {
            @Bindable var model = model
            VStack(alignment: .leading, spacing: 16) {
                Text("Sift keeps the text of each link on this Mac, so it stays after a tab closes. Search and Claude read this library. Saving does not use Claude.")
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        option(Toggle("Save the text of every link", isOn: $model.state.autoCapture),
                               "One Markdown file per link. Sift fetches each page once and goes slowly with each site.")
                        Divider()
                        option(Toggle("Save YouTube transcripts", isOn: $model.state.youtubeTranscripts),
                               "Uses the open-source youtube-transcript-api tool, which needs Python 3. It reads captions in a way YouTube has not approved, so it can stop working.")
                        if TranscriptTool.executable == nil {
                            install("Install Transcript Tool", message: model.transcriptToolMessage) { await model.installTranscriptTool() }
                        }
                        Divider()
                        option(Toggle("Save Instagram post images", isOn: $model.state.instagramImages),
                               "Instagram's image links expire, so Sift keeps a copy.")
                        Divider()
                        option(Toggle("Save what reels say", isOn: $model.state.reelTranscripts),
                               "The open-source yt-dlp tool fetches each reel's audio, macOS speech recognition writes it down, and Sift deletes the audio.")
                        if ReelTool.executable == nil {
                            install("Install Reel Tool", message: model.reelToolMessage) { await model.installReelTool() }
                        }
                    }
                    .padding(6)
                }

                HStack {
                    Text("~/Library/Application Support/Sift/Library").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Library.folder]) }
                }
            }
        }

        private func option(_ toggle: Toggle<Text>, _ text: String) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                toggle
                Text(text)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }

        private func install(_ label: String, message: String?, action: @escaping @MainActor () async -> Void) -> some View {
            HStack {
                Button(label) { Task { await action() } }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.leading, 20)
        }
    }
}
