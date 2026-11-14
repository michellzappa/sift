import SwiftUI

/// Settings > Claude > On this Mac: Apple's on-device model, one switch per
/// feature, its availability in plain words, and who sorted how many links.
struct OnDeviceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let status = LocalModel.status
        let available = status == .available
        Section {
            LabeledContent("Apple's on-device model", value: status.label)
            Toggle("Spot errands and noise first", isOn: $model.state.localFirstPass)
                .disabled(!available)
            Toggle("Sort into your themes first", isOn: $model.state.localSorting)
                .disabled(!available)
            Toggle("Summarize saved pages and transcripts", isOn: $model.state.localSummaries)
                .disabled(!available)
            LabeledContent("Sorted on this Mac") {
                let moved = model.deviceSortedMovedCount
                Text("\(model.deviceSortedCount) links" + (moved > 0 ? ", you moved \(moved) by hand" : ""))
            }
            LabeledContent("Sorted by Claude", value: "\(model.claudeSortedCount) links")
            LabeledContent("Summaries", value: "\(model.summaryCount) of \(model.capturedCount) saved links")
            if model.isSummarizing {
                ProgressView(value: Double(model.summaryProgress.done), total: Double(max(model.summaryProgress.total, 1))) {
                    Text("Summarizing \(model.summaryProgress.done) of \(model.summaryProgress.total)").font(.caption)
                }
            }
        } header: {
            Text("On this Mac")
        } footer: {
            Text(Self.footer(status))
                .foregroundStyle(.secondary)
        }
    }

    static func footer(_ status: LocalModel.Status) -> String {
        switch status {
        case .available:
            "Apple's model runs on your Mac, for free, and works offline. Nothing leaves the Mac. When it is unsure about a link, Claude sorts it as before. Summaries wait while the Mac runs on battery."
        case .appleIntelligenceOff:
            "Turn on Apple Intelligence in System Settings to use these. Until then Claude sorts every link."
        case .notReady:
            "macOS is still downloading the model. Until it is ready, Claude sorts every link."
        case .notSupported, .needsNewerMacOS:
            "Claude sorts every link on this Mac."
        }
    }
}
