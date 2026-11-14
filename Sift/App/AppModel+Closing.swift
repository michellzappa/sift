import Foundation

extension AppModel {
    // MARK: Closing on the iPhone and in Chrome

    var currentChrome: ChromeReader.Profile? {
        guard let id = state.deviceID, id.hasPrefix(ChromeReader.sourcePrefix) else { return nil }
        return chromeProfiles.first { $0.id == id }
    }

    /// The source shown now is a Chrome profile.
    var isChrome: Bool { state.deviceID?.hasPrefix(ChromeReader.sourcePrefix) == true }

    /// The name of a Chrome profile: the user's own, else "Profile 2" when
    /// one browser has several, else nothing.
    func chromeProfileName(_ p: ChromeReader.Profile) -> String? {
        if let name = state.chromeProfileNames[p.install], !name.isEmpty { return name }
        let same = chromeProfiles.filter { $0.browser == p.browser }
        guard same.count > 1, let i = same.firstIndex(of: p) else { return nil }
        return "Profile \(i + 1)"
    }

    func setChromeProfileName(_ name: String, for p: ChromeReader.Profile) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        state.chromeProfileNames[p.install] = clean.isEmpty ? nil : clean
    }

    func removeChromeProfile(_ p: ChromeReader.Profile) {
        ChromeReader.remove(p)
        state.chromeProfileNames[p.install] = nil
        if state.deviceID == p.id { state.deviceID = Self.allSourcesID }
        reload()
    }

    /// Writes the helper's host manifest for each Chromium browser, copies
    /// the extension, shows it in Finder and opens the extensions page.
    func installChromeHelper() {
        guard !Demo.isOn else { chromeHelperMessage = Demo.offMessage; return }
        do {
            let browsers = try ChromeHelper.install()
            guard !browsers.isEmpty else {
                chromeHelperMessage = "Sift found no Chrome, Brave, Edge, Arc, Vivaldi or Chromium on this Mac."
                return
            }
            chromeHelperMessage = "Helper installed for \(browsers.map(\.name).formatted(.list(type: .and)))."
            ChromeHelper.revealExtension()
            ChromeHelper.openExtensionsPage()
        } catch {
            chromeHelperMessage = "Could not install the helper: \(error.localizedDescription)"
        }
    }

    /// The extension reports every minute while Chrome runs, but the host
    /// rewrites a snapshot only when the tabs change. Sift looks every 30
    /// seconds and reloads at most every two minutes, never while Claude works.
    func startChromeWatcher() {
        guard !Demo.isOn else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                let latest = ChromeReader.latestChange()
                guard latest != lastChromeChange, Date().timeIntervalSince(lastChromeReload) > 120,
                      !isSorting, !isDiscovering else { continue }
                lastChromeReload = .now
                reload()
            }
        }
    }

    /// A tab Sift closes in Chrome rather than on the iPhone: it is open in
    /// Chrome and not on a Safari device.
    func closesInChrome(_ tab: SafariTab) -> Bool {
        tab.source.hasPrefix(ChromeReader.sourcePrefix) || (chromeOpenURLs.contains(tab.url) && !safariOpenURLs.contains(tab.url))
    }

    func closeLabel(_ tab: SafariTab) -> String {
        let queued = isQueuedToClose(tab)
        if closesInChrome(tab) { return queued ? "Keep Open in Chrome" : "Close in Chrome" }
        return queued ? "Keep Open on iPhone" : "Close on iPhone"
    }

    /// Queued URLs open in Chrome. The extension closes them within a minute.
    var chromeCloseCount: Int { state.closeQueue.filter(chromeOpenURLs.contains).count }

    /// Queued URLs for the iPhone Shortcut.
    var iPhoneCloseQueue: [String] {
        state.closeQueue.filter { !(chromeOpenURLs.contains($0) && !safariOpenURLs.contains($0)) }
    }

    /// Routes the close queue: Chrome's tabs to chrome/close.json, the rest
    /// to the iPhone's close.txt. A URL open in both goes to both.
    func writeCloseLists() {
        CloseList.write(iPhoneCloseQueue)
        ChromeReader.writeClose(state.closeQueue.filter(chromeOpenURLs.contains))
    }

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
}
