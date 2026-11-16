import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var state: SiftState {
        didSet {
            StateFile.save(state)
            if state.closeQueue != oldValue.closeQueue { writeCloseLists() }
        }
    }
    var previews: [String: Preview] = PreviewFetcher.loadCache()
    var fetchingPreviews = 0
    var devices: [SyncedDevice] = []
    var tabs: [SafariTab] = [] {
        didSet { duplicateGroups = Self.duplicates(in: tabs) }
    }
    var loadError: CloudTabsReader.Failure?

    var isSorting = false
    /// True while Apple's on-device model sorts, before Claude gets the rest.
    var sortingOnDevice = false
    var sortProgress: (done: Int, total: Int) = (0, 0)
    var sortError: String?

    /// The Setup Guide as it stands in this run (see Onboarding.swift).
    var onboarding: OnboardingSession?
    /// The guide window is open. The main window then leaves ThemeReview to it.
    var onboardingOpen = false

    // X
    var xPosts: [String: XPost] = XStore.load()
    var xBookmarkIDs: [String] = XStore.loadBookmarks()
    var xBusy = false
    var xError: String?

    // Sources
    private(set) var readingListCount = 0
    private(set) var allSourcesCount = 0

    // Instagram Saved and archive
    var archive: [String: ArchiveRecord] = ArchiveStore.load()
    private(set) var instagramCount = 0
    /// Why the chosen export could not be read, for Settings.
    var instagramError: String?

    // Library
    var library: [String: Library.Entry] = Library.loadIndex()
    var isCapturing = false
    var captureProgress: (done: Int, total: Int) = (0, 0)
    /// On-device summaries (see AppModel+LocalModel.swift).
    var isSummarizing = false
    var summaryProgress: (done: Int, total: Int) = (0, 0)
    var isTranscribing = false
    var transcriptProgress: (done: Int, total: Int) = (0, 0)
    var transcriptTried = Set<String>()
    /// Problems reading or saving Sift's own files, not yet shown.
    var dataProblem: String?
    var shownProblems = 0
    var isFetchingVideoTitles = false
    var videoTitleTried = Set<String>()
    var transcriptToolMessage: String?
    var isTranscribingReels = false
    var reelProgress: (done: Int, total: Int) = (0, 0)
    var reelTried = Set<String>()
    var reelToolMessage: String?
    var isFetchingInstagramImages = false
    var instagramImageProgress: (done: Int, total: Int) = (0, 0)
    var instagramImageTried = Set<String>()
    // TikTok (AppModel+TikTok)
    private(set) var tiktokCount = 0
    var tiktokCounts = TikTokReader.Counts()
    var tiktokError: String?
    var isFetchingTikTok = false
    var tiktokProgress: (done: Int, total: Int) = (0, 0)
    var tiktokTried = Set<String>()

    // Imports
    private(set) var importCounts: [String: Int] = [:]
    var importError: String?

    // Send
    var sendError: String?
    /// URLs being sent right now, for a spinner on their rows.
    var sending = Set<String>()

    // Themes and connections
    var isDiscovering = false
    var themeProposal: [Sorter.ThemeProposal]?
    /// The proposal adds themes for unsorted links and keeps the current ones
    /// (`discoverNewThemes`), instead of replacing the set.
    var themeProposalAdditive = false
    /// The URLs the proposal's item ids point at, in order.
    var proposalURLs: [String] = []
    /// The theme the graph is zoomed into. The sidebar selects it too.
    var graphTheme: String?

    var isConnecting = false
    var connectProgress: (done: Int, total: Int) = (0, 0)

    // Upkeep and search
    /// Links here that are the same page as another link here. Worked out
    /// when the tabs change, not on every redraw.
    private(set) var duplicateGroups: [[SafariTab]] = []
    var indexTask: Task<Void, Never>?

    // Closing
    /// Chrome profiles that report their open tabs, from the extension.
    private(set) var chromeProfiles: [ChromeReader.Profile] = []
    /// URLs open in any Chrome profile, and on any Safari device.
    private(set) var chromeOpenURLs = Set<String>()
    private(set) var safariOpenURLs = Set<String>()
    private(set) var lastChromeChange: Date?
    var lastChromeReload = Date.distantPast
    /// What Install Chrome Helper did, for Settings and the Setup Guide.
    var chromeHelperMessage: String?

    // Export
    var exportMessage: String?

    // MARK: Feeds (AppModel+Feeds.swift, Engine/Feeds.swift)
    var isFetchingFeeds = false
    /// Items held per feed (feed id → count), for the sidebar totals.
    /// Refreshed after each check, follow and unfollow (`refreshFeedCounts`).
    var feedItemCounts: [String: Int] = [:]
    /// Bumped when a feed icon arrives, so rows draw it.
    var feedIconVersion = 0
    /// Opens the Add Feed sheet (toolbar, File menu, Settings).
    var showAddFeed = false
    /// The Scan / Watch / Read switch over every list (nil = All). One
    /// setting for Today, feeds and the library, kept across launches.
    var listMode: ReadingMode? = ReadingMode(rawValue: UserDefaults.standard.string(forKey: "list.mode") ?? "") {
        didSet { UserDefaults.standard.set(listMode?.rawValue ?? "", forKey: "list.mode") }
    }
    /// Ask the main window to show a sidebar item (keyboard shortcuts, the
    /// command palette). ContentView applies it and sets it back to nil.
    var navigationRequest: SidebarItem?
    /// The sidebar item on screen (ContentView keeps it current), for J/K.
    @ObservationIgnored var currentSidebar: SidebarItem?
    /// The keyboard shortcuts sheet (?).
    var showShortcuts = false
    /// The "How Today Works" sheet (Views/HowTodayWorks.swift).
    var showHowToday = false
    /// The ⌘K command palette is open (Views/CommandPalette.swift).
    var showPalette = false
    /// The page for Sift's browser window (Views/BrowserWindow.swift).
    /// Originals open there, not in Safari, so they do not come back as tabs.
    var browserURL: URL?
    /// Bumped on each request, so the window opens again for the same URL.
    var browserRequest = 0
    /// A notice that fades (AppModel+Feeds `note`), shown at the window's foot.
    var notice: String?
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    @ObservationIgnored var recentFollows: [String] = []
    var feedProgress: (done: Int, total: Int) = (0, 0)

    // MARK: Seen (AppModel+Seen.swift, Storage/Seen.swift)
    /// Newest seen or unseen mark per URL, from every device.
    var seenMarks: [String: SeenMark] = [:]
    /// The marks this Mac made: its own file in iCloud Drive/Sift/seen.
    @ObservationIgnored var ownSeen: [String: SeenMark] = [:]
    @ObservationIgnored var seenSaveTask: Task<Void, Never>?
    /// Agent requests from sift-mcp (AppModel+Agent.swift).
    @ObservationIgnored var agentSource: DispatchSourceFileSystemObject?
    @ObservationIgnored var agentBusy = false
    /// Theme proposals made for an agent, by proposal id, until applied.
    @ObservationIgnored var agentProposals: [String: (proposals: [Sorter.ThemeProposal], urls: [String])] = [:]

    init() {
        if Demo.isOn { Demo.start() }
        state = StateFile.load()
        loadSeen()
        if !Demo.isOn { Task { await migrateStarlingsDestinations() } }
        if state.today == nil { pruneOfferedFromArchive() }
        refreshFeedCounts()
        // 1.2 keeps each item's full text. Feeds fetched before would answer
        // 304 (unchanged) and never send it: fetch them all again once.
        // 1.4.3 keeps the newest 20 items at any age: fetch again once so
        // quiet blogs get their older posts.
        if !UserDefaults.standard.bool(forKey: "feeds.contentV4") {
            for i in state.feeds.indices {
                state.feeds[i].etag = nil; state.feeds[i].lastModified = nil; state.feeds[i].lastFetched = nil
            }
            UserDefaults.standard.set(true, forKey: "feeds.contentV4")
        }
        reload()
        settleOnboardingForExistingInstall()
        // Demo mode has no background jobs and no Chrome.
        if !Demo.isOn {
            TelemetryCoordinator.shared.start(self)
            UpdateChecker.shared.start()
            startLibraryWorker()
            startChromeWatcher()
            startAgentWatcher()
        }
    }

    // MARK: Loading

    func reload() {
        do {
            // Safari's tab database needs Full Disk Access. Without it the
            // other sources (Instagram, imports, X) still load; the Setup
            // Guide and a banner explain the missing access.
            do {
                devices = try CloudTabsReader.devices()
                loadError = nil
            } catch let failure as CloudTabsReader.Failure {
                loadError = failure
                devices = []
            } catch {
                loadError = .sqlite(error.localizedDescription)
                devices = []
            }
            // Every device's open tabs, so the close list keeps what is still open.
            safariOpenURLs = Set(devices.flatMap { (try? CloudTabsReader.tabs(deviceID: $0.id)) ?? [] }.map(\.url))
            chromeProfiles = ChromeReader.profiles()
            chromeOpenURLs = Set(chromeProfiles.flatMap(\.tabs).map(\.url))
            lastChromeChange = ChromeReader.latestChange()
            let readingItems = (try? ReadingListReader.items()) ?? []
            readingListCount = readingItems.count
            // Instagram Saved: read the export once per reload. Without a
            // readable export the source falls back to the phone.
            let instagram = instagramItems()
            instagramCount = instagram.count
            if isInstagram && instagram.isEmpty { state.deviceID = nil }
            let tiktok = tiktokItems()
            tiktokCount = tiktok.count
            if isTikTok && tiktok.isEmpty { state.deviceID = nil }
            let lists = myLists.map { ($0, listTabs($0)) }
            if state.deviceID?.hasPrefix(Self.listPrefix) == true, currentList == nil { state.deviceID = nil }
            // Unique links across every source, for the All Sources label.
            var everyURL = Set(readingItems.map(\.tab.url))
            everyURL.formUnion(instagram.map(\.tab.url))
            everyURL.formUnion(tiktok.map(\.tab.url))
            for (_, tabs) in lists { everyURL.formUnion(tabs.map(\.url)) }
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
            everyURL.formUnion(chromeOpenURLs)
            allSourcesCount = everyURL.count
            if state.deviceID == nil {
                state.deviceID = Self.allSourcesID
            } else if !isAll, !isSavedList, currentImport == nil, currentChrome == nil, !devices.contains(where: { $0.id == state.deviceID }) {
                // The device with the most tabs is almost always the phone.
                state.deviceID = devices.first?.id ?? Self.allSourcesID
            }
            if isAll {
                // Every source at once, newest first, each link once.
                var seen = Set<String>()
                var all: [SafariTab] = []
                func add(_ list: [SafariTab], _ source: String) {
                    for var t in list where seen.insert(t.url).inserted { t.source = source; all.append(t) }
                }
                if let phone = devices.first { add(try CloudTabsReader.tabs(deviceID: phone.id), "tabs:\(phone.id)") }
                for profile in chromeProfiles { add(profile.tabs, profile.id) }
                let reading = (try? ReadingListReader.items()) ?? []
                for item in reading + instagram + tiktok where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
                add(reading.map(\.tab), "reading-list")
                add(instagram.map(\.tab), "instagram")
                add(tiktok.map(\.tab), "tiktok")
                for (feed, tabs) in lists { add(tabs, Self.listPrefix + feed.id) }
                add(xBookmarkTabs(), "x")
                add(keptTabs(), TodayStore.keptSourceID)
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
            } else if isKept {
                tabs = keptTabs()
            } else if isXBookmarks {
                tabs = xBookmarkTabs()
            } else if let profile = currentChrome {
                tabs = profile.tabs
            } else if let list = currentList {
                tabs = lists.first { $0.0.id == list.id }?.1 ?? []
            } else if isTikTok {
                tabs = tiktok.map(\.tab)
                for item in tiktok where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
            } else if isInstagram {
                tabs = instagram.map(\.tab)
                // The export carries author, caption and collection; use them until Sift fetches its own.
                for item in instagram where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
            } else if isReadingList {
                let items = (try? ReadingListReader.items()) ?? []
                tabs = items.map(\.tab)
                // Safari stores preview text for Reading List items; use it until Sift fetches its own.
                for item in items where previews[item.tab.url] == nil {
                    if let p = item.preview { previews[item.tab.url] = p }
                }
            } else {
                tabs = try state.deviceID.map { try CloudTabsReader.tabs(deviceID: $0) } ?? []
            }
            // Tabs closed on the phone or in Chrome drop out of the close
            // list. Without Safari's tabs Sift cannot tell, so it keeps them.
            if loadError == nil {
                let open = safariOpenURLs.union(chromeOpenURLs)
                let stillOpen = state.closeQueue.filter(open.contains)
                if stillOpen != state.closeQueue { state.closeQueue = stillOpen }
            }
            writeCloseLists()
            if !isAll {
                let key = currentSourceKey
                tabs = tabs.map { var t = $0; t.source = key; return t }
            }
            // Merged duplicates hide while the link they were merged into is here.
            let here = Set(tabs.map(\.url))
            tabs.removeAll { state.mergedInto[$0.url].map(here.contains) ?? false }
            recordArchive()
            separateErrands()
            scheduleSearchIndex()
            if state.findConnections, !isConnecting, !linksNeedingConnections.isEmpty {
                Task { await findConnections() }
            }
            startLibraryJobs()
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
            s.assignments[tab.url] = Assignment(project: Project.errands, use: "", manual: false, action: nil)
            changed = true
        }
        if changed { state = s }
    }
}
