import AppKit
import Foundation
import UniformTypeIdentifiers

/// Who you follow on each network (issue #39): read from the exports and
/// the public Bluesky and Mastodon APIs (Storage/FollowingReader.swift),
/// kept in following.json, followed as feeds where a feed exists, and
/// added to People as places. The monthly export reminder (issue #43) is
/// here too; the Downloads watcher is in AppModel+Downloads.
extension AppModel {
    /// What to read per network: an export path, or a handle.
    func followingSource(_ n: FollowNetwork) -> String? {
        let s: String? = switch n {
        case .youtube: state.following.youtubeTakeoutPath
        case .instagram: state.instagramExportPath
        case .tiktok: state.tiktokExportPath
        case .x: state.following.xArchivePath
        case .bluesky: state.following.blueskyHandle
        case .mastodon: state.following.mastodonHandle
        }
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }

    func follows(_ n: FollowNetwork) -> NetworkFollows? { followingData[n.rawValue] }

    /// Reads each network whose export changed (path or file date) or whose
    /// handle changed; Bluesky and Mastodon again after a day. Runs with the
    /// library jobs, so a new export chosen in Settings is read on reload.
    func refreshFollowing(force: Bool = false) {
        guard !Demo.isOn, !isReadingFollowing else { return }
        var jobs: [(FollowNetwork, String, String)] = []
        var removed = false
        for n in FollowNetwork.allCases {
            guard let src = followingSource(n) else {
                if followingData.removeValue(forKey: n.rawValue) != nil { removed = true }
                continue
            }
            let sig = n.isExport ? src + "|" + String(Int(ExportFile.date(of: src)?.timeIntervalSince1970 ?? 0)) : src.lowercased()
            let old = followingData[n.rawValue]
            let daily = !n.isExport && Date().timeIntervalSince(old?.read ?? .distantPast) > 86_400
            if force || old?.signature != sig || daily { jobs.append((n, src, sig)) }
        }
        if removed { FollowingStore.save(followingData); mergePeople() }
        guard !jobs.isEmpty else { return }
        isReadingFollowing = true
        let todo = jobs
        Task { [weak self] in
            let results = await Self.readFollowing(todo)
            guard let self else { return }
            for (n, r) in results {
                var r = r
                // A network that did not answer keeps what Sift read before.
                if r.error != nil, r.accounts.isEmpty, let old = self.followingData[n.rawValue], !n.isExport { r.accounts = old.accounts }
                self.followingData[n.rawValue] = r
            }
            FollowingStore.save(self.followingData)
            self.isReadingFollowing = false
            self.followImported()
            self.mergePeople()
        }
    }

    /// Off the main actor for exports (a Takeout can be gigabytes); through
    /// HostGate for Bluesky and Mastodon.
    nonisolated static func readFollowing(_ jobs: [(FollowNetwork, String, String)]) async -> [(FollowNetwork, NetworkFollows)] {
        var out: [(FollowNetwork, NetworkFollows)] = []
        for (n, src, sig) in jobs {
            var r = NetworkFollows(read: Date(), signature: sig)
            do {
                switch n {
                case .bluesky: r.accounts = try await FollowingReader.bluesky(handle: src)
                case .mastodon: r.accounts = try await FollowingReader.mastodon(handle: src)
                case .youtube, .instagram, .tiktok, .x:
                    r.accounts = try await Task.detached(priority: .utility) { () throws -> [FollowedAccount] in
                        switch n {
                        case .youtube: try FollowingReader.youtube(at: src)
                        case .instagram: try FollowingReader.instagram(at: src)
                        case .tiktok: try FollowingReader.tiktok(at: src)
                        default: try FollowingReader.x(at: src)
                        }
                    }.value
                    r.exportDate = ExportFile.date(of: src)
                }
                r.newest = r.accounts.compactMap(\.since).max()
            } catch {
                r.error = error.localizedDescription
                if n.isExport { r.exportDate = ExportFile.date(of: src) }
            }
            out.append((n, r))
        }
        return out
    }

    /// Follows each imported account that has a feed, once. Sift never
    /// follows an account again after you unfollow it. New feeds go in one
    /// folder per network ("YouTube subscriptions", "Bluesky follows") and
    /// are fetched with the next feed check.
    func followImported() {
        guard !Demo.isOn, state.following.followAsFeeds else { return }
        var s = state
        var done = Set(s.following.followed)
        let urls = Set(s.feeds.map { $0.url.lowercased() })
        let places = Set(s.feeds.compactMap(\.place))
        var added = 0
        for n in FollowNetwork.allCases where n.hasFeeds {
            for a in followingData[n.rawValue]?.accounts ?? [] {
                guard let url = a.feedURL, done.insert(a.place.id).inserted else { continue }
                if urls.contains(url.lowercased()) || places.contains(a.place.id) { continue }
                s.feeds.append(Feed(id: UUID().uuidString.prefix(8).lowercased(), url: url, title: a.name, site: a.place.url,
                                    category: n.folder, provider: n.rawValue, place: a.place.id, added: Date()))
                added += 1
            }
        }
        guard done.count != s.following.followed.count else { return }
        s.following.followed = done.sorted()
        state = s
        guard added > 0 else { return }
        note("Following \(added) account\(added == 1 ? "" : "s") you follow elsewhere")
        refreshFeedCounts()
        Task { await fetchFeeds() }
    }

    /// Place keys for the accounts you follow: the place id, and for YouTube
    /// the channel id, so a person's channel under its @handle matches too.
    var followedPlaceKeys: [String: FollowNetwork] {
        var out: [String: FollowNetwork] = [:]
        for n in FollowNetwork.allCases {
            for a in followingData[n.rawValue]?.accounts ?? [] {
                out[a.place.id] = n
                if n == .youtube, let id = People.channelID(a.place.url) { out["channel:" + id] = n }
            }
        }
        return out
    }

    /// The network you follow a place on, if any.
    func followedNetwork(of p: Place, keys: [String: FollowNetwork]) -> FollowNetwork? {
        if let n = keys[p.id] { return n }
        if p.platform == "youtube", let id = People.channelID(p.url) { return keys["channel:" + id] }
        return nil
    }

    /// "You follow them on X" in each person who has a place you follow.
    func withFollowEvidence(_ people: [Person]) -> [Person] {
        let keys = followedPlaceKeys
        guard !keys.isEmpty else { return people }
        return people.map { person in
            var p = person
            for place in person.profiles {
                guard let n = followedNetwork(of: place, keys: keys) else { continue }
                let line = "You follow them on \(n.name)"
                if !p.evidence.contains(line) { p.evidence.insert(line, at: 0) }
            }
            return p
        }
    }

    /// YouTube channels and Bluesky accounts you follow, as People seeds:
    /// their About page or profile says where else they publish.
    func followingSeeds() -> [(profile: Place, name: String)] {
        [FollowNetwork.youtube, .bluesky].flatMap { n in (followingData[n.rawValue]?.accounts ?? []).map { ($0.place, $0.name) } }
    }

    /// The networks where you follow a Your Graph creator.
    func followedNetworks(of c: Creator) -> [FollowNetwork] {
        var out: [FollowNetwork] = []
        if let n = followedPlaceKeys[c.id] { out.append(n) }
        if c.id.hasPrefix("youtube:") {
            let flat = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
            if follows(.youtube)?.accounts.contains(where: { flat($0.name) == flat(c.name) }) == true, !out.contains(.youtube) { out.append(.youtube) }
        }
        if let person = person(forCreator: c) {
            let keys = followedPlaceKeys
            for p in person.profiles { if let n = followedNetwork(of: p, keys: keys), !out.contains(n) { out.append(n) } }
        }
        return out
    }

    // MARK: Status (Settings > Inputs)

    /// "312 channels · export of 5 Nov 2026 · newest follow 2 Nov".
    func followingStatus(_ n: FollowNetwork) -> String {
        guard followingSource(n) != nil else { return n.isExport ? "No export chosen" : "No handle" }
        guard let f = follows(n) else { return isReadingFollowing ? "Reading…" : "Not read yet" }
        if let e = f.error, f.accounts.isEmpty { return e }
        let noun = n == .youtube ? "channel" : "account"
        var parts = ["\(f.accounts.count) \(noun)\(f.accounts.count == 1 ? "" : "s")"]
        if let d = f.exportDate { parts.append("export of \(d.formatted(date: .abbreviated, time: .omitted))") }
        else { parts.append("read \(f.read.formatted(.relative(presentation: .named)))") }
        if let d = f.newest { parts.append("newest follow \(d.formatted(date: .abbreviated, time: .omitted))") }
        if n.hasFeeds {
            let places = Set(state.feeds.compactMap(\.place))
            let urls = Set(state.feeds.map(\.url))
            let followed = f.accounts.filter { places.contains($0.place.id) || $0.feedURL.map(urls.contains) == true }.count
            parts.append("\(followed) followed as feeds")
        }
        return parts.joined(separator: " · ")
    }

    func isStale(_ n: FollowNetwork) -> Bool {
        guard n.isExport, let src = followingSource(n), let d = ExportFile.date(of: src) else { return false }
        return Date().timeIntervalSince(d) > Self.staleDays * 86_400
    }

    // MARK: Choosing exports

    /// Asks for the X archive (the zip X sends, or its folder).
    func chooseXArchive() {
        guard let url = pickExport(message: "Choose your X archive: the zip X sends after Download an archive of your data, or the folder it unpacks to.",
                                   last: state.following.xArchivePath) else { return }
        state.following.xArchivePath = Self.keepCopy(of: url).path(percentEncoded: false)
        refreshFollowing()
    }

    /// Asks for a Google Takeout export with YouTube subscriptions.
    func chooseYouTubeTakeout() {
        guard let url = pickExport(message: "Choose your Google Takeout export with YouTube and YouTube Music: the zip or the folder it unpacks to.",
                                   last: state.following.youtubeTakeoutPath) else { return }
        setTakeout(Self.keepCopy(of: url).path(percentEncoded: false))
        reload()
    }

    /// One Takeout serves both: subscriptions (this file) and playlists
    /// (LinkImporter's YouTube source, updated to the newer copy, or added).
    func setTakeout(_ path: String) {
        state.following.youtubeTakeoutPath = path
        if let items = try? YouTubeTakeout.items(at: path), !items.isEmpty {
            if let i = state.importedSources.firstIndex(where: { $0.name.hasPrefix("YouTube") }) {
                state.importedSources[i].path = path
            } else {
                state.importedSources.append(LinkImporter.Source(id: UUID().uuidString, name: "YouTube", path: path, added: .now))
            }
        }
    }

    /// The Choose… action for each export network.
    func chooseExport(_ n: FollowNetwork) {
        switch n {
        case .youtube: chooseYouTubeTakeout()
        case .instagram: chooseInstagramExport()
        case .tiktok: chooseTikTokExport()
        case .x: chooseXArchive()
        case .bluesky, .mastodon: return
        }
        if exportReminder == n { exportReminder = nil }
    }

    /// How many days old the network's export is.
    func exportAgeDays(_ n: FollowNetwork) -> Int? {
        guard let src = followingSource(n), let d = ExportFile.date(of: src) else { return nil }
        return Int(Date().timeIntervalSince(d) / 86_400)
    }

    func clearFollowing(_ n: FollowNetwork) {
        switch n {
        case .youtube: state.following.youtubeTakeoutPath = nil
        case .x: state.following.xArchivePath = nil
        case .bluesky: state.following.blueskyHandle = ""
        case .mastodon: state.following.mastodonHandle = ""
        case .instagram, .tiktok: return
        }
        refreshFollowing()
    }

    private func pickExport(message: String, last: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.prompt = "Choose"
        panel.message = message
        if let last { panel.directoryURL = URL(filePath: last).deletingLastPathComponent() }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: Monthly reminder (issue #43)

    /// An export older than this is stale; Sift reminds once per this many days.
    static let staleDays: Double = 30

    /// Shows one reminder for the first stale export network, at most once
    /// a month per network. Runs with the library jobs.
    func checkExportReminders() {
        guard !Demo.isOn, exportReminder == nil else { return }
        for n in FollowNetwork.allCases where isStale(n) {
            if let last = state.following.reminded[n.rawValue], Date().timeIntervalSince(last) < Self.staleDays * 86_400 { continue }
            state.following.reminded[n.rawValue] = Date()
            exportReminder = n
            return
        }
    }
}
