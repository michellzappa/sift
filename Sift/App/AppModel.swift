import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var state: SiftState {
        didSet {
            StateFile.save(state)
            if state.closeQueue != oldValue.closeQueue { CloseList.write(state.closeQueue) }
        }
    }
    var previews: [String: Preview] = PreviewFetcher.loadCache()
    var fetchingPreviews = 0
    var devices: [SyncedDevice] = []
    var tabs: [SafariTab] = []
    var repoProjects: [Project] = []
    var loadError: CloudTabsReader.Failure?

    var isSorting = false
    var sortProgress: (done: Int, total: Int) = (0, 0)
    var sortError: String?

    init() {
        state = StateFile.load()
        reload()
    }

    // MARK: Loading

    func reload() {
        repoProjects = ProjectScanner.scan(root: URL(filePath: state.projectsRoot, directoryHint: .isDirectory))
        do {
            devices = try CloudTabsReader.devices()
            readingListCount = (try? ReadingListReader.items().count) ?? 0
            loadError = nil
            if state.deviceID == nil || (!isReadingList && !devices.contains(where: { $0.id == state.deviceID })) {
                // The device with the most tabs is almost always the phone.
                state.deviceID = devices.first?.id
            }
            if isReadingList {
                let items = try ReadingListReader.items()
                tabs = items.map(\.tab)
                // Safari stores preview text for Reading List items; use it until Sift fetches its own.
                for item in items where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
            } else {
                tabs = try state.deviceID.map { try CloudTabsReader.tabs(deviceID: $0) } ?? []
                // Tabs closed on the phone drop out of the close list.
                let open = Set(tabs.map(\.url))
                let stillOpen = state.closeQueue.filter(open.contains)
                if stillOpen != state.closeQueue { state.closeQueue = stillOpen }
            }
        } catch let failure as CloudTabsReader.Failure {
            loadError = failure
            devices = []
            tabs = []
        } catch {
            loadError = .sqlite(error.localizedDescription)
        }
    }

    func selectDevice(_ id: String) {
        state.deviceID = id
        reload()
    }

    /// True when the source is Safari's Reading List, not a device's open tabs.
    var isReadingList: Bool { state.deviceID == ReadingListReader.sourceID }

    private(set) var readingListCount = 0

    // MARK: Sites and actions

    /// Sites with at least three tabs, biggest first. The rest count as "other".
    var sites: [(host: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tab in tabs { counts[tab.host, default: 0] += 1 }
        return counts.filter { $0.value >= 3 }.map { ($0.key, $0.value) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    func tabs(onSite host: String) -> [SafariTab] { tabs.filter { $0.host == host } }

    func tabs(withAction action: NextAction) -> [SafariTab] {
        tabs.filter { state.assignments[$0.url]?.action == action }
    }

    func setAction(_ action: NextAction?, for tab: SafariTab) {
        guard var a = state.assignments[tab.url] else { return }
        a.action = action
        state.assignments[tab.url] = a
    }

    /// Sorted tabs that have no next action yet (for example from a CSV import).
    var tabsWithoutAction: [SafariTab] {
        tabs.filter { tab in
            guard let a = state.assignments[tab.url] else { return false }
            return a.action == nil && a.project != Project.unknown
        }
    }

    func suggestActions() async {
        guard !isSorting else { return }
        let todo = tabsWithoutAction
        guard !todo.isEmpty else { return }
        isSorting = true
        sortError = nil
        sortProgress = (0, todo.count)
        defer { isSorting = false }
        let sorter = Sorter(backend: state.backend)
        for start in stride(from: 0, to: todo.count, by: Sorter.batchSize) {
            let batch = Array(todo[start..<min(start + Sorter.batchSize, todo.count)])
            let rows = batch.map { tab in
                (item: sortItem(tab), project: state.assignments[tab.url]?.project ?? "", use: state.assignments[tab.url]?.use ?? "")
            }
            do {
                let result = try await sorter.suggestActions(rows)
                for (url, action) in result where state.assignments[url]?.action == nil {
                    state.assignments[url]?.action = action
                }
                sortProgress.done = min(start + batch.count, todo.count)
            } catch {
                sortError = error.localizedDescription
                return
            }
        }
    }

    // MARK: Projects

    /// Projects the sorter and the sidebar use, in name order.
    var projects: [Project] {
        let hidden = Set(state.hiddenProjects)
        let repos = repoProjects.filter { !hidden.contains($0.name) }
        let repoNames = Set(repos.map(\.name))
        return (repos + state.extraProjects.filter { !repoNames.contains($0.name) })
            .sorted { $0.name < $1.name }
    }

    func assignment(for tab: SafariTab) -> Assignment? { state.assignments[tab.url] }

    func tabs(in project: String?) -> [SafariTab] {
        guard let project else { return tabs.filter { state.assignments[$0.url] == nil } }
        return tabs.filter { state.assignments[$0.url]?.project == project }
    }

    var unsortedCount: Int { tabs.filter { state.assignments[$0.url] == nil }.count }

    func count(_ project: String) -> Int { tabs.filter { state.assignments[$0.url]?.project == project }.count }

    /// Projects that hold at least one tab, biggest first.
    var activeProjects: [(project: String, count: Int)] {
        var counts: [String: Int] = [:]
        for tab in tabs { if let p = state.assignments[tab.url]?.project { counts[p, default: 0] += 1 } }
        return counts.filter { !Project.buckets.contains($0.key) }
            .map { ($0.key, $0.value) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    func move(_ tab: SafariTab, to project: String) {
        let old = state.assignments[tab.url]
        let use = Project.buckets.contains(project) ? "" : (old?.use ?? "")
        let action = project == Project.drop ? .close : old?.action
        state.assignments[tab.url] = Assignment(project: project, use: use, manual: true, action: action)
    }

    func setUse(_ use: String, for tab: SafariTab) {
        guard var a = state.assignments[tab.url] else { return }
        a.use = use
        a.manual = true
        state.assignments[tab.url] = a
    }

    func addProject(name: String, summary: String) {
        let clean = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !clean.isEmpty, !Project.buckets.contains(clean), !projects.contains(where: { $0.name == clean }) else { return }
        state.extraProjects.append(Project(name: clean, summary: summary, isRepo: false))
    }

    func removeExtraProject(_ name: String) {
        state.extraProjects.removeAll { $0.name == name }
    }

    func setHidden(_ name: String, hidden: Bool) {
        state.hiddenProjects.removeAll { $0 == name }
        if hidden { state.hiddenProjects.append(name) }
    }

    // MARK: Sorting

    /// Sorts every tab that has no assignment yet. Hand-sorted tabs stay as they are.
    func sortUnsorted() async {
        guard !isSorting else { return }
        let todo = tabs.filter { state.assignments[$0.url] == nil }
        guard !todo.isEmpty else { return }

        isSorting = true
        sortError = nil
        sortProgress = (0, todo.count)
        defer { isSorting = false }

        let sorter = Sorter(backend: state.backend)
        let projects = self.projects
        for start in stride(from: 0, to: todo.count, by: Sorter.batchSize) {
            let batch = Array(todo[start..<min(start + Sorter.batchSize, todo.count)])
            do {
                let result = try await sorter.sort(batch.map(sortItem), projects: projects)
                for (url, a) in result where state.assignments[url]?.manual != true {
                    state.assignments[url] = a
                }
                sortProgress.done = min(start + batch.count, todo.count)
            } catch {
                sortError = error.localizedDescription
                return
            }
        }
    }

    private func sortItem(_ tab: SafariTab) -> Sorter.Item {
        let p = previews[tab.url]
        let title = tab.hasUsefulTitle ? tab.title : (p?.title ?? "")
        return Sorter.Item(url: tab.url, title: title, preview: p?.failed == false ? p?.text ?? "" : "")
    }

    /// Fetches previews for the tabs that have none yet, six at a time.
    func fetchPreviews(for list: [SafariTab], force: Bool = false) async {
        let todo = list.map(\.url).filter { force || previews[$0] == nil }
        guard !todo.isEmpty else { return }
        fetchingPreviews += todo.count
        await withTaskGroup(of: (String, Preview).self) { group in
            var iterator = todo.makeIterator()
            for _ in 0..<6 {
                guard let url = iterator.next() else { break }
                group.addTask { (url, await PreviewFetcher.fetch(url)) }
            }
            for await (url, preview) in group {
                previews[url] = preview
                fetchingPreviews -= 1
                if let next = iterator.next() { group.addTask { (next, await PreviewFetcher.fetch(next)) } }
            }
        }
        PreviewFetcher.saveCache(previews)
    }

    func preview(for tab: SafariTab) async {
        if previews[tab.url] == nil { await fetchPreviews(for: [tab]) }
    }

    /// Fetches previews for the "unknown" tabs, then sorts them again with the
    /// preview text. Tabs that stay unknown are probably deleted posts.
    func resortUnknown() async {
        let unknown = tabs(in: Project.unknown)
        guard !unknown.isEmpty, !isSorting else { return }
        await fetchPreviews(for: unknown)
        for tab in unknown { state.assignments[tab.url] = nil }
        await sortUnsorted()
    }

    // MARK: Closing on the iPhone

    func isQueuedToClose(_ tab: SafariTab) -> Bool { state.closeQueue.contains(tab.url) }

    func toggleClose(_ tab: SafariTab) {
        if let i = state.closeQueue.firstIndex(of: tab.url) { state.closeQueue.remove(at: i) } else { state.closeQueue.append(tab.url) }
    }

    func queueClose(_ list: [SafariTab]) {
        let existing = Set(state.closeQueue)
        state.closeQueue += list.map(\.url).filter { !existing.contains($0) }
    }

    func unqueueClose(_ list: [SafariTab]) {
        let remove = Set(list.map(\.url))
        state.closeQueue.removeAll { remove.contains($0) }
    }

    var closeQueueTabs: [SafariTab] {
        let q = Set(state.closeQueue)
        return tabs.filter { q.contains($0.url) }
    }

    // MARK: Import and export

    /// Imports a CSV with the columns project, title, url, possible use.
    /// Imported rows count as hand-sorted.
    func importCSV(from url: URL) throws -> Int {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = CSV.parse(text)
        guard let header = rows.first?.map({ $0.lowercased() }),
              let p = header.firstIndex(of: "project"), let u = header.firstIndex(of: "url")
        else { throw Sorter.Failure(message: "The CSV needs a header row with project and url columns.") }
        let useIndex = header.firstIndex(where: { $0.contains("use") })
        var count = 0
        for row in rows.dropFirst() where row.count > max(p, u) {
            let project = row[p].trimmingCharacters(in: .whitespaces).lowercased()
            guard !project.isEmpty else { continue }
            if !Project.buckets.contains(project), !projects.contains(where: { $0.name == project }) {
                addProject(name: project, summary: "")
            }
            let use = useIndex.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
            state.assignments[row[u]] = Assignment(project: project, use: use, manual: true, action: project == Project.drop ? .close : nil)
            count += 1
        }
        return count
    }

    func markdown(for project: String) -> String {
        var lines = ["## \(project)", ""]
        for tab in tabs(in: project) {
            let use = state.assignments[tab.url]?.use ?? ""
            lines.append("- [\(tab.displayTitle.prefix(100))](\(tab.url))" + (use.isEmpty ? "" : ": \(use)"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    var allMarkdown: String {
        let names = activeProjects.map(\.project) + Project.buckets
        return names.map { markdown(for: $0) }.joined(separator: "\n")
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Minimal RFC 4180 CSV parser: quoted fields, doubled quotes, CRLF.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character?
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = chars.next() {
                        if n == "\"" { field.append("\"") } else { quoted = false; pending = n }
                    } else { quoted = false }
                } else { field.append(c) }
                continue
            }
            switch c {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
