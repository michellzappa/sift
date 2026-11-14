import Foundation

/// Apple's on-device model in the app: the first pass and theme picks before
/// Claude sorts, and summaries of the library. See `LocalModel`.
extension AppModel {
    // MARK: Sorting on this Mac

    /// Sorts what the on-device model is sure about and returns those URLs.
    /// First pass: sure errands go to errands, sure noise to drop. Then, with
    /// themes, a sure pick goes into that theme. Everything else is left for
    /// Claude. Assignments are not `manual` and carry `sortedBy: "device"`.
    func sortOnDevice(_ items: [Sorter.Item]) async -> Set<String> {
        guard !Demo.isOn else { return [] }
        let hints = state.localSorting
            ? themes.map { LocalModel.ThemeHint(name: $0.name, summary: $0.summary, notes: $0.notes) }
            : []
        guard LocalModel.isAvailable, state.localFirstPass || !hints.isEmpty, !items.isEmpty else { return [] }
        sortingOnDevice = true
        sortProgress = (0, items.count)
        defer { sortingOnDevice = false }

        var handled = Set<String>()
        var pending: [String: Assignment] = [:]
        func flush() {
            guard !pending.isEmpty else { return }
            var s = state
            for (url, a) in pending where s.assignments[url] == nil { s.assignments[url] = a }
            state = s
            pending = [:]
        }
        for item in items {
            sortProgress.done += 1
            guard state.assignments[item.url] == nil else { continue }
            if state.localFirstPass,
               let v = await LocalModel.firstPass(title: item.title, url: item.url, preview: item.preview),
               v.sure, v.kind != .keep {
                let bucket = v.kind == .errand ? Project.errands : Project.drop
                pending[item.url] = Assignment(project: bucket, use: "", manual: false, action: nil, sortedBy: "device")
                handled.insert(item.url)
            } else if !hints.isEmpty,
                      let pick = await LocalModel.pickTheme(title: item.title, url: item.url, preview: item.preview, themes: hints),
                      pick.sure {
                pending[item.url] = Assignment(project: pick.theme, use: "", manual: false, action: nil, sortedBy: "device")
                handled.insert(item.url)
            }
            if pending.count >= 10 { flush() }
        }
        flush()
        return handled
    }

    /// Links the on-device model sorted, and how many of those the owner
    /// moved by hand afterwards (a rough disagreement count).
    var deviceSortedCount: Int { state.assignments.values.filter { $0.sortedBy == "device" }.count }
    var deviceSortedMovedCount: Int { state.assignments.values.filter { $0.sortedBy == "device" && $0.manual }.count }
    var claudeSortedCount: Int { state.assignments.values.filter { $0.sortedBy == "claude" }.count }

    // MARK: Summaries

    /// Captured links with enough text and no summary attempt yet, newest first.
    var linksToSummarize: [String] {
        library.filter { _, e in
            e.summary == nil && !e.file.isEmpty && (e.status == "ok" || e.status == "thin") && e.words >= 120
        }
        .map(\.key)
        .sorted { (archive[$0]?.firstSeen ?? .distantPast) > (archive[$1]?.firstSeen ?? .distantPast) }
    }

    var summaryCount: Int { library.values.filter { !($0.summary ?? "").isEmpty }.count }

    /// Summarizes library files on device, one at a time, newest first, with
    /// a pause between files. Waits while the Mac runs on battery. Stops when
    /// the model is busy or rate limited; the next reload or capture resumes.
    func summarizeLibrary() async {
        guard !Demo.isOn else { return }
        guard state.localSummaries, !isSummarizing, LocalModel.isAvailable, !LocalModel.onBattery else { return }
        let todo = linksToSummarize
        guard !todo.isEmpty else { return }
        isSummarizing = true
        summaryProgress = (0, todo.count)
        defer { isSummarizing = false; Library.saveIndex(library); scheduleSearchIndex() }
        for url in todo {
            guard state.localSummaries, !LocalModel.onBattery else { return }
            guard let entry = library[url], entry.summary == nil else { summaryProgress.done += 1; continue }
            let title = archive[url]?.title ?? ""
            let text = await Task.detached(priority: .utility) { Library.text(for: url) ?? "" }.value
            let outcome = await LocalModel.summarize(title: title, text: text)
            // The file may have been captured again meanwhile.
            guard var current = library[url], current.file == entry.file else { continue }
            switch outcome {
            case .summary(let summary) where !summary.isEmpty:
                current.summary = summary
                Library.setSummary(summary, file: current.file)
            case .summary, .skip:
                current.summary = ""
            case .later:
                return
            }
            library[url] = current
            summaryProgress.done += 1
            if summaryProgress.done % 10 == 0 { Library.saveIndex(library); scheduleSearchIndex() }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
