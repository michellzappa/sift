import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

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
        do {
            devices = try CloudTabsReader.devices()
            let readingItems = (try? ReadingListReader.items()) ?? []
            readingListCount = readingItems.count
            // Instagram Saved: read the export once per reload. Without a
            // readable export the source falls back to the phone.
            let instagram = instagramItems()
            instagramCount = instagram.count
            if isInstagram && instagram.isEmpty { state.deviceID = nil }
            // Unique links across every source, for the All Sources label.
            var everyURL = Set(readingItems.map(\.tab.url))
            everyURL.formUnion(instagram.map(\.tab.url))
            everyURL.formUnion(xBookmarkTabs().map(\.url))
            importCounts = [:]
            for source in state.importedSources {
                let urls = importedItems(source).map(\.tab.url)
                importCounts[source.id] = urls.count
                everyURL.formUnion(urls)
            }
            if let phone = devices.first, let phoneTabs = try? CloudTabsReader.tabs(deviceID: phone.id) {
                everyURL.formUnion(phoneTabs.map(\.url))
            }
            allSourcesCount = everyURL.count
            loadError = nil
            if state.deviceID == nil {
                state.deviceID = Self.allSourcesID
            } else if !isAll, !isSavedList, currentImport == nil, !devices.contains(where: { $0.id == state.deviceID }) {
                // The device with the most tabs is almost always the phone.
                state.deviceID = devices.first?.id
            }
            if isAll {
                // Every source at once, newest first, each link once.
                var seen = Set<String>()
                var all: [SafariTab] = []
                func add(_ list: [SafariTab], _ source: String) {
                    for var t in list where seen.insert(t.url).inserted { t.source = source; all.append(t) }
                }
                if let phone = devices.first { add(try CloudTabsReader.tabs(deviceID: phone.id), "tabs:\(phone.id)") }
                let reading = (try? ReadingListReader.items()) ?? []
                for item in reading + instagram where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
                add(reading.map(\.tab), "reading-list")
                add(instagram.map(\.tab), "instagram")
                add(xBookmarkTabs(), "x")
                for source in state.importedSources {
                    let items = importedItems(source)
                    for item in items where previews[item.tab.url] == nil {
                        if let p = item.preview { previews[item.tab.url] = p }
                    }
                    add(items.map(\.tab), LinkImporter.sourcePrefix + source.id)
                }
                tabs = all.sorted { ($0.lastViewed ?? .distantPast) > ($1.lastViewed ?? .distantPast) }
            } else if let source = currentImport {
                let items = importedItems(source)
                tabs = items.map(\.tab)
                for item in items where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
            } else if isXBookmarks {
                tabs = xBookmarkTabs()
            } else if isInstagram {
                tabs = instagram.map(\.tab)
                // The export carries author, caption and collection; use them until Sift fetches its own.
                for item in instagram where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
            } else if isReadingList {
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
            if !isAll {
                let key = currentSourceKey
                tabs = tabs.map { var t = $0; t.source = key; return t }
            }
            recordArchive()
            separateErrands()
            // New links go into the library in the background.
            if state.autoCapture, !isCapturing, !linksToCapture.isEmpty {
                Task { await captureAll() }
            }
        } catch let failure as CloudTabsReader.Failure {
            loadError = failure
            devices = []
            tabs = []
        } catch {
            loadError = .sqlite(error.localizedDescription)
        }
    }

    /// Moves transactional tabs to the errands bucket, except ones the user
    /// sorted by hand.
    private func separateErrands() {
        var s = state
        var changed = false
        for tab in tabs where Errands.isErrand(tab.url) {
            let a = s.assignments[tab.url]
            guard a?.manual != true, a?.project != Project.errands else { continue }
            s.assignments[tab.url] = Assignment(project: Project.errands, use: "", manual: false, action: .close)
            changed = true
        }
        if changed { state = s }
    }

    func selectDevice(_ id: String) {
        state.deviceID = id
        reload()
    }

    /// True when the source is Safari's Reading List, not a device's open tabs.
    var isReadingList: Bool { state.deviceID == ReadingListReader.sourceID }

    // MARK: X API (opt-in, the user's own X developer app)

    static let xBookmarksSourceID = "x-bookmarks"
    var isXBookmarks: Bool { state.deviceID == Self.xBookmarksSourceID }
    var xPosts: [String: XPost] = XStore.load()
    var xBookmarkIDs: [String] = XStore.loadBookmarks()
    var xBusy = false
    var xError: String?

    /// True when the user connected their own X app and signed in.
    var xConnected: Bool { !state.xClientID.isEmpty && state.xUserID != nil }

    func connectX() async {
        guard !state.xClientID.isEmpty else { xError = "Paste your X app's Client ID first."; return }
        xBusy = true
        defer { xBusy = false }
        do {
            _ = try await XAuth.signIn(clientID: state.xClientID)
            let me = try await XClient(clientID: state.xClientID).me()
            state.xUserID = me.id
            state.xUsername = me.username
            xError = nil
        } catch {
            xError = error.localizedDescription
        }
    }

    func disconnectX() {
        XAuth.store(nil)
        state.xUserID = nil
        state.xUsername = nil
        if isXBookmarks { state.deviceID = nil; reload() }
    }

    /// The cached post behind an X status URL, if any.
    func xPost(for url: String) -> XPost? { XClient.statusID(url).flatMap { xPosts[$0] } }

    /// Fetches posts that are missing or older than `XStore.maxAge`, in
    /// batches of 100, and turns them into previews. Posts the API no longer
    /// returns lose their content.
    func refreshXPosts(urls: [String], force: Bool = false) async {
        guard xConnected else { return }
        let ids = Array(Set(urls.compactMap(XClient.statusID))).filter { id in
            guard !force, let p = xPosts[id] else { return true }
            return Date().timeIntervalSince(p.fetched) > XStore.maxAge
        }
        guard !ids.isEmpty else { return }
        do {
            let result = try await XClient(clientID: state.xClientID).lookup(ids)
            for p in result.posts { xPosts[p.id] = p }
            for id in result.missing { xPosts[id] = .removedStub(id) }
            XStore.save(xPosts)
            for url in urls { if let p = xPost(for: url) { previews[url] = preview(from: p) } }
            PreviewFetcher.saveCache(previews)
        } catch {
            xError = error.localizedDescription
        }
    }

    private func preview(from p: XPost) -> Preview {
        if p.removed {
            return Preview(title: "", text: "", imageURL: nil, site: "x.com", fetched: p.fetched, failed: true)
        }
        let quoted = p.quotedID.flatMap { xPosts[$0] }
        let image = p.media.first.flatMap { $0.url ?? $0.preview } ?? quoted?.media.first.flatMap { $0.url ?? $0.preview }
        let text = XPostView.attributed(p).characters.map(String.init).joined()
        return Preview(title: p.author?.name ?? "X", text: text, imageURL: image, site: "x.com", fetched: p.fetched,
                       avatarURL: p.author?.avatar, links: p.links.filter { !$0.isMedia }.map(\.expanded))
    }

    /// Downloads the user's most recent bookmarks (X returns up to 800).
    func syncXBookmarks() async {
        guard xConnected, let userID = state.xUserID else { return }
        xBusy = true
        defer { xBusy = false }
        do {
            let result = try await XClient(clientID: state.xClientID).bookmarks(userID: userID)
            for p in result.posts { xPosts[p.id] = p }
            XStore.save(xPosts)
            xBookmarkIDs = result.order
            XStore.saveBookmarks(xBookmarkIDs)
            for id in result.order { if let p = xPosts[id] { previews[p.permalink] = preview(from: p) } }
            PreviewFetcher.saveCache(previews)
            xError = nil
            if isXBookmarks { reload() }
        } catch {
            xError = error.localizedDescription
        }
    }

    private func xBookmarkTabs() -> [SafariTab] {
        xBookmarkIDs.compactMap { id in
            guard let p = xPosts[id], !p.removed else { return nil }
            let title = "\(p.author?.name ?? "X") on X: \(p.text.prefix(120))"
            return SafariTab(url: p.permalink, title: title, lastViewed: p.created)
        }
    }

    private(set) var readingListCount = 0

    // MARK: Instagram Saved

    /// True when the source is Instagram's saved posts from the data export.
    var isInstagram: Bool { state.deviceID == InstagramReader.sourceID }

    /// True when the source is a saved list (Reading List, Instagram Saved),
    /// not a device's open tabs. Saved lists have nothing to close on the iPhone.
    // MARK: Archive

    var archive: [String: ArchiveRecord] = ArchiveStore.load()

    /// The source key a link is recorded under: "tabs:<device>",
    /// "reading-list", "instagram", "x" or "import:<id>".
    private var currentSourceKey: String {
        if isReadingList { return "reading-list" }
        if isInstagram { return "instagram" }
        if isXBookmarks { return "x" }
        if let source = currentImport { return LinkImporter.sourcePrefix + source.id }
        return "tabs:\(state.deviceID ?? "")"
    }

    /// The sources whose full list is loaded right now, so a record missing
    /// from them really left (and is not just in another source).
    private var loadedSourceKeys: Set<String> {
        guard isAll else { return [currentSourceKey] }
        var keys: Set<String> = ["reading-list", "instagram", "x"]
        if let phone = devices.first { keys.insert("tabs:\(phone.id)") }
        for s in state.importedSources { keys.insert(LinkImporter.sourcePrefix + s.id) }
        return keys
    }

    /// Records every link the current view shows, and archives the records
    /// of links that left a loaded source. Called on every reload.
    private func recordArchive() {
        let now = Date()
        let present = Set(tabs.map(\.url))
        for tab in tabs {
            var r = archive[tab.url] ?? ArchiveRecord(url: tab.url, title: tab.title, source: tab.source, firstSeen: tab.lastViewed ?? now)
            let p = previews[tab.url]
            if tab.hasUsefulTitle { r.title = tab.title } else if let p, !p.failed, !p.title.isEmpty { r.title = p.title }
            if let a = state.assignments[tab.url] { r.theme = a.project; r.use = a.use; r.action = a.action }
            if let p, !p.failed { r.previewText = p.text; r.imageURL = p.imageURL ?? p.avatarURL }
            r.lastSeen = now
            r.archived = nil
            archive[tab.url] = r
        }
        let loaded = loadedSourceKeys
        for (url, r) in archive where r.archived == nil && loaded.contains(r.source) && !present.contains(url) {
            archive[url]?.archived = now
        }
        ArchiveStore.save(archive)
        // Archived links show from their record when no preview is cached.
        for r in archive.values where r.isArchived && previews[r.url] == nil && !r.previewText.isEmpty {
            previews[r.url] = Preview(title: r.title, text: r.previewText, imageURL: r.imageURL, site: r.asTab.host, fetched: r.lastSeen)
        }
    }

    /// Links that left their source, newest first.
    var archivedTabs: [SafariTab] {
        archive.values.filter(\.isArchived).sorted { ($0.archived ?? .distantPast) > ($1.archived ?? .distantPast) }.map(\.asTab)
    }

    func archiveRecord(for url: String) -> ArchiveRecord? { archive[url] }

    // MARK: Capture (the library engine, step 1)

    var library: [String: Library.Entry] = Library.loadIndex()
    var isCapturing = false
    var captureProgress: (done: Int, total: Int) = (0, 0)

    /// Links worth capturing: everything Sift has seen, minus errands, drop,
    /// and links captured already (failed ones retry after a week).
    var linksToCapture: [ArchiveRecord] {
        archive.values.filter { r in
            guard r.theme != Project.errands, r.theme != Project.drop, !Errands.isErrand(r.url) else { return false }
            guard let e = library[r.url] else { return true }
            // Posts captured as thin before posts were exempt: redo once.
            if e.status == "thin", Self.isPostURL(r.url) { return true }
            // Failed posts that now have known text (an Instagram caption) retry now.
            if e.status == "failed", Self.isPostURL(r.url), !(previews[r.url]?.text ?? "").isEmpty { return true }
            return e.status == "failed" && Date().timeIntervalSince(e.captured) > 7 * 24 * 3600
        }
    }

    /// Fetches and extracts the text of every link not yet in the library,
    /// four at a time, and writes it as Markdown. Local only: no Claude.
    func captureAll() async {
        guard !isCapturing else { return }
        let todo = linksToCapture
        guard !todo.isEmpty else { return }
        isCapturing = true
        captureProgress = (0, todo.count)
        defer { isCapturing = false; Library.saveIndex(library) }
        // Posts (X, Instagram) are captured from the text Sift already has:
        // their pages need a login or JavaScript.
        let jobs: [(ArchiveRecord, String?)] = todo.map { r in
            guard Self.isPostURL(r.url) else { return (r, nil) }
            let text = xPost(for: r.url).map { XPostView.attributed($0).characters.map(String.init).joined() } ?? previews[r.url]?.text
            return (r, text?.isEmpty == false ? text : nil)
        }
        await withTaskGroup(of: (ArchiveRecord, Capture?).self) { group in
            var iterator = jobs.makeIterator()
            func next(_ job: (ArchiveRecord, String?)) {
                let (r, known) = job
                group.addTask { (r, await Capturer.capture(r.url, knownText: known)) }
            }
            for _ in 0..<4 { if let j = iterator.next() { next(j) } }
            for await (r, capture) in group {
                if let capture {
                    library[r.url] = Library.write(capture, title: r.title, theme: r.theme, source: r.source)
                } else {
                    library[r.url] = Library.Entry(file: "", captured: .now, words: 0, kind: "page", status: "failed")
                }
                captureProgress.done += 1
                if captureProgress.done % 25 == 0 { Library.saveIndex(library) }
                if let j = iterator.next() { next(j) }
            }
        }
    }

    static func isPostURL(_ url: String) -> Bool {
        if XClient.statusID(url) != nil { return true }
        let host = URL(string: url)?.host()?.lowercased() ?? ""
        return host.hasSuffix("instagram.com")
    }

    var capturedCount: Int { library.values.filter { $0.status != "failed" }.count }

    static let allSourcesID = "all-sources"
    private(set) var allSourcesCount = 0
    /// Phone tabs, Reading List, Instagram Saved and X Bookmarks together.
    var isAll: Bool { state.deviceID == Self.allSourcesID }

    /// Sources that are lists, not open tabs: nothing to close on a phone.
    var isSavedList: Bool { isReadingList || isInstagram || isXBookmarks || currentImport != nil }

    // MARK: Imported link files

    private(set) var importCounts: [String: Int] = [:]
    var importError: String?

    var currentImport: LinkImporter.Source? {
        guard let id = state.deviceID, id.hasPrefix(LinkImporter.sourcePrefix) else { return nil }
        return state.importedSources.first { LinkImporter.sourcePrefix + $0.id == id }
    }

    private func importedItems(_ source: LinkImporter.Source) -> [LinkImporter.Item] {
        (try? LinkImporter.items(at: source.path)) ?? []
    }

    /// Asks for an export file (CSV, JSON or bookmark HTML), checks that it
    /// has links, adds it as a source and switches to it.
    func importLinksFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json, .html, .plainText, .zip, .folder]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose an export from Instapaper, Pocket, Readwise, Raindrop, Pinboard, a bookmarks file, or a Google Takeout zip with YouTube playlists."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path(percentEncoded: false)
        do {
            _ = try LinkImporter.items(at: path)
            let source = LinkImporter.Source(id: UUID().uuidString, name: LinkImporter.suggestedName(for: path), path: path, added: .now)
            state.importedSources.append(source)
            importError = nil
            state.deviceID = LinkImporter.sourcePrefix + source.id
            reload()
        } catch {
            importError = error.localizedDescription
            sortError = error.localizedDescription
        }
    }

    func removeImport(_ source: LinkImporter.Source) {
        state.importedSources.removeAll { $0.id == source.id }
        if currentImport == nil, state.deviceID?.hasPrefix(LinkImporter.sourcePrefix) == true { state.deviceID = Self.allSourcesID }
        reload()
    }

    private(set) var instagramCount = 0
    /// Why the chosen export could not be read, for Settings.
    private(set) var instagramError: String?

    private func instagramItems() -> [InstagramReader.Item] {
        guard let path = state.instagramExportPath else { instagramError = nil; return [] }
        do {
            let items = try InstagramReader.items(at: path)
            instagramError = nil
            return items
        } catch {
            instagramError = error.localizedDescription
            return []
        }
    }

    /// Asks for the Instagram export (the zip or its unpacked folder) and shows it as a source.
    func chooseInstagramExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.prompt = "Choose"
        panel.message = "Choose your Instagram export: the zip, or the folder it unpacks to."
        if let last = state.instagramExportPath { panel.directoryURL = URL(filePath: last).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.instagramExportPath = url.path(percentEncoded: false)
        reload()
    }

    func clearInstagramExport() {
        state.instagramExportPath = nil
        reload()
    }

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

    /// The themes Sift sorts into, in name order. Themes come from the
    /// user's own links; there is no fixed list.
    var projects: [Project] { themes.sorted { $0.name < $1.name } }

    var themes: [Project] { state.extraProjects.filter(\.isTheme) }

    /// Places links can end up, added by hand. Used only as hints when
    /// Claude suggests a home for a theme.
    var destinations: [Project] { state.extraProjects.filter { !$0.isTheme } }

    // MARK: Themes

    var isDiscovering = false
    var themeProposal: [Sorter.ThemeProposal]?
    /// The URLs the proposal's item ids point at, in order.
    private(set) var proposalURLs: [String] = []

    /// Reads every link Sift can see (the phone's tabs, the Reading List and Instagram Saved),
    /// fills in titles for bare links, and asks Claude for themes. The result
    /// waits in `themeProposal` until the user accepts it.
    func discoverThemes() async {
        guard !isDiscovering, !isSorting else { return }
        isDiscovering = true
        sortError = nil
        defer { isDiscovering = false }

        var corpus: [SafariTab] = []
        var seen = Set<String>()
        func add(_ list: [SafariTab]) { for t in list where seen.insert(t.url).inserted { corpus.append(t) } }
        if let phone = devices.first, let phoneTabs = try? CloudTabsReader.tabs(deviceID: phone.id) { add(phoneTabs) }
        if let reading = try? ReadingListReader.items() {
            for item in reading where previews[item.tab.url] == nil { if let p = item.preview { previews[item.tab.url] = p } }
            add(reading.map(\.tab))
        }
        let instagram = instagramItems()
        for item in instagram where previews[item.tab.url] == nil { if let p = item.preview { previews[item.tab.url] = p } }
        add(instagram.map(\.tab))
        add(xBookmarkTabs())
        for source in state.importedSources {
            let items = importedItems(source)
            for item in items where previews[item.tab.url] == nil { if let p = item.preview { previews[item.tab.url] = p } }
            add(items.map(\.tab))
        }
        add(tabs)

        // Transactional tabs are not curiosity: they skip Claude entirely.
        corpus.removeAll { Errands.isErrand($0.url) }

        // Bare links (mostly X posts) say nothing without their text.
        await fetchPreviews(for: corpus.filter { !$0.hasUsefulTitle })

        do {
            let result = try await Sorter(backend: state.backend)
                .discoverThemes(corpus.map(sortItem), destinations: destinations, keep: themes)
            proposalURLs = corpus.map(\.url)
            themeProposal = result.sorted { $0.itemIDs.count > $1.itemIDs.count }
        } catch {
            sortError = error.localizedDescription
        }
    }

    /// Makes the accepted themes Sift's categories. Links in a "personal" or
    /// "noise" theme go to the personal and drop buckets. Links in a theme the
    /// user left out become unsorted. Uses and next actions stay.
    func applyThemes(_ accepted: [Sorter.ThemeProposal]) {
        var s = state
        s.extraProjects.removeAll(where: \.isTheme)
        let acceptedIDs = Set(accepted.flatMap(\.itemIDs))
        for proposal in themeProposal ?? [] {
            let isAccepted = accepted.contains { $0.itemIDs == proposal.itemIDs }
            if !isAccepted {
                for id in proposal.itemIDs where proposalURLs.indices.contains(id) && !acceptedIDs.contains(id) {
                    s.assignments[proposalURLs[id]] = nil
                }
            }
        }
        for theme in accepted {
            let bucket: String? = switch theme.kind {
            case "noise": Project.drop
            case "personal": Project.personal
            case "errand": Project.errands
            default: nil
            }
            let name = bucket ?? theme.name
            if bucket == nil {
                s.extraProjects.append(Project(name: theme.name, summary: theme.description, destination: theme.destination))
            }
            for id in theme.itemIDs where proposalURLs.indices.contains(id) {
                let url = proposalURLs[id]
                var a = s.assignments[url] ?? Assignment(project: name, use: "", manual: false, action: nil)
                a.project = name
                a.manual = false
                if bucket != nil { a.use = "" }
                if bucket == Project.drop { a.action = .close }
                s.assignments[url] = a
            }
        }
        state = s
        themeProposal = nil
    }

    /// Deletes one theme. Its links become unsorted.
    func removeTheme(_ name: String) {
        var s = state
        s.extraProjects.removeAll { $0.isTheme && $0.name == name }
        for (url, a) in s.assignments where a.project == name { s.assignments[url] = nil }
        state = s
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

    /// Adds a theme by hand.
    func addTheme(name: String, summary: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !Project.buckets.contains(clean.lowercased()),
              !state.extraProjects.contains(where: { $0.name.lowercased() == clean.lowercased() }) else { return }
        state.extraProjects.append(Project(name: clean, summary: summary))
    }

    func renameTheme(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != old, !state.extraProjects.contains(where: { $0.name == clean }) else { return }
        var s = state
        if let i = s.extraProjects.firstIndex(where: { $0.isTheme && $0.name == old }) { s.extraProjects[i].name = clean }
        for (url, a) in s.assignments where a.project == old { s.assignments[url]?.project = clean }
        state = s
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
        var preview = p?.failed == false ? p?.text ?? "" : ""
        if let out = p?.outboundURL { preview += " (links to \(out))" }
        return Sorter.Item(url: tab.url, title: title, preview: preview)
    }

    /// Fetches previews for the tabs that have none yet, six at a time.
    func fetchPreviews(for list: [SafariTab], force: Bool = false) async {
        var todo = list.map(\.url).filter { force || previews[$0] == nil || needsLinks($0) }
        // With the X API connected, X posts come from the API in batches.
        if xConnected {
            let xURLs = todo.filter { XClient.statusID($0) != nil }
            if !xURLs.isEmpty {
                await refreshXPosts(urls: xURLs, force: force)
                todo.removeAll { XClient.statusID($0) != nil }
            }
        }
        guard !todo.isEmpty else { return }
        fetchingPreviews += todo.count
        let xSyndication = state.xSyndication
        await withTaskGroup(of: (String, Preview).self) { group in
            var iterator = todo.makeIterator()
            for _ in 0..<6 {
                guard let url = iterator.next() else { break }
                group.addTask { (url, await PreviewFetcher.fetch(url, xSyndication: xSyndication)) }
            }
            for await (url, preview) in group {
                previews[url] = preview
                fetchingPreviews -= 1
                if let next = iterator.next() { group.addTask { (next, await PreviewFetcher.fetch(next, xSyndication: xSyndication)) } }
            }
        }
        PreviewFetcher.saveCache(previews)
    }

    /// Turns the X syndication previews on or off. Turning them on drops the
    /// cached X previews that have no image (oEmbed never returns one) and
    /// fetches them again for the loaded tabs.
    func setXSyndication(_ on: Bool) {
        state.xSyndication = on
        guard on else { return }
        let stale = Set(previews.filter { $0.value.site == "x.com" && $0.value.imageURL == nil }.keys)
        guard !stale.isEmpty else { return }
        for url in stale { previews[url] = nil }
        PreviewFetcher.saveCache(previews)
        let refetch = tabs.filter { stale.contains($0.url) }
        Task { await fetchPreviews(for: refetch) }
    }

    func preview(for tab: SafariTab) async {
        if previews[tab.url] == nil || needsLinks(tab.url) { await fetchPreviews(for: [tab]) }
    }

    /// X previews cached before link extraction existed get one refetch.
    private func needsLinks(_ url: String) -> Bool {
        guard state.xSyndication, let p = previews[url] else { return false }
        return p.site == "x.com" && !p.failed && p.links == nil
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

    // MARK: Exporters

    var exportMessage: String?

    /// What every exporter receives: sorted links in themes and the personal
    /// bucket, never drop, unknown or unsorted ones.
    func exportSnapshot() -> ExportSnapshot {
        let source = isReadingList ? "reading-list" : isInstagram ? InstagramReader.sourceID : (devices.first { $0.id == state.deviceID }?.name ?? "tabs")
        let items: [ExportItem] = tabs.compactMap { tab in
            guard let a = state.assignments[tab.url], a.project != Project.drop, a.project != Project.unknown,
                  a.project != Project.errands else { return nil }
            let p = previews[tab.url]
            let usable = p?.failed == false ? p : nil
            let title = tab.hasUsefulTitle ? tab.title : (usable.map { $0.site == "x.com" ? "\($0.title) on X" : $0.title } ?? tab.url)
            return ExportItem(url: tab.url, title: title, theme: a.project, use: a.use, action: a.action?.rawValue ?? "",
                              site: tab.host, source: source, lastViewed: tab.lastViewed,
                              previewText: usable?.text ?? "", imageURL: usable?.imageURL)
        }
        var themeList = projects.map { theme in
            ExportTheme(name: theme.name, summary: theme.summary, destination: theme.destination,
                        count: items.filter { $0.theme == theme.name }.count)
        }
        let personal = items.filter { $0.theme == Project.personal }.count
        if personal > 0 { themeList.append(ExportTheme(name: Project.personal, summary: "Personal life, not a theme.", destination: "", count: personal)) }
        return ExportSnapshot(created: .now, themes: themeList.filter { $0.count > 0 }, items: items)
    }

    /// Asks for a folder or file when the exporter needs one, runs it, and
    /// shows its message.
    func runExport(_ exporter: any Exporter) {
        let snapshot = exportSnapshot()
        guard !snapshot.items.isEmpty else { exportMessage = "Nothing to export yet. Sort some tabs first."; return }
        var target: URL?
        switch exporter.output {
        case .clipboard:
            break
        case .folder:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export Here"
            panel.message = "\(exporter.name.replacingOccurrences(of: "…", with: "")): choose a folder"
            if let last = state.exportTargets[exporter.id] { panel.directoryURL = URL(filePath: last) }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            target = url
        case .file(let ext):
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Sift \(ExportText.day.string(from: .now)).\(ext)"
            panel.canCreateDirectories = true
            if let last = state.exportTargets[exporter.id] { panel.directoryURL = URL(filePath: last) }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            target = url
        }
        do {
            let result = try exporter.export(snapshot, to: target)
            if case .clipboard = exporter.output {
                copy(result)
                exportMessage = "Copied \(snapshot.items.count) links."
            } else {
                exportMessage = result
                if let t = target {
                    let remember = (exporter.output.isFolder ? t : t.deletingLastPathComponent()).path(percentEncoded: false)
                    state.exportTargets[exporter.id] = remember
                }
            }
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
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
                addTheme(name: project, summary: "")
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
