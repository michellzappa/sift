import Foundation

// Who the person follows on each network (issue #39, ADR 0001 decisions 4
// and 11). Exports only for YouTube, Instagram, TikTok and X; the public
// APIs for Bluesky and Mastodon, with the person's own handle. Sift never
// logs in to Instagram, TikTok or X and never uses browser cookies. Each
// account becomes a `Place` (Feeds/People.swift); AppModel+Following
// follows the ones that have a feed.

/// One file inside an export: a zip (read with /usr/bin/unzip, never
/// unpacked to disk) or the folder it unpacks to. InstagramReader,
/// TikTokReader and FollowingReader read through it.
enum ExportFile {
    /// One member of the zip (a pattern like "*saved/x.json" is allowed;
    /// more than one match comes back joined). Nil when it is not there.
    static func unzip(_ zip: String, member: String) throws -> Data? {
        let data = try run("/usr/bin/unzip", ["-p", zip, member])
        return data.status == 0 ? data.out : nil
    }

    /// Every member name in the zip. Empty for a file that is not a
    /// complete zip (a download still in progress).
    static func members(_ zip: String) -> [String] {
        guard let r = try? run("/usr/bin/zipinfo", ["-1", zip]), r.status == 0 else { return [] }
        return String(decoding: r.out, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// The first file found: in a folder, at one of `folderPaths` (relative)
    /// or, failing that, any file below whose path ends with one of them;
    /// in a zip, the first member that matches `zipMember`.
    static func data(at path: String, folderPaths: [String], zipMember: String) throws -> Data? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        guard isDir.boolValue else { return try unzip(path, member: zipMember) }
        let root = URL(filePath: path, directoryHint: .isDirectory)
        for rel in folderPaths {
            if let d = FileManager.default.contents(atPath: root.appending(path: rel).path(percentEncoded: false)) { return d }
        }
        // Google Takeout and X put a top folder above the files.
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let file as URL in walker {
            let p = file.path(percentEncoded: false).lowercased()
            if folderPaths.contains(where: { p.hasSuffix("/" + $0.lowercased()) }) { return FileManager.default.contents(atPath: file.path(percentEncoded: false)) }
        }
        return nil
    }

    /// Every file in a folder export whose path matches `test` (lowercased path).
    static func files(in folder: String, where test: (String) -> Bool) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: URL(filePath: folder, directoryHint: .isDirectory), includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let file as URL in walker where test(file.path(percentEncoded: false).lowercased()) { out.append(file) }
        return out
    }

    /// When the export was made: the file's (or folder's) modification
    /// date. A copy in Imports keeps the date of the download.
    static func date(of path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private static func run(_ tool: String, _ args: [String]) throws -> (out: Data, status: Int32) {
        let p = Process()
        p.executableURL = URL(filePath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        // Read before waiting so a full pipe cannot block the child.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (data, p.terminationStatus)
    }
}

/// The networks Sift reads a following list from.
enum FollowNetwork: String, CaseIterable, Codable, Sendable, Identifiable {
    case youtube, instagram, tiktok, x, bluesky, mastodon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .youtube: "YouTube"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .x: "X"
        case .bluesky: "Bluesky"
        case .mastodon: "Mastodon"
        }
    }

    var symbol: String {
        switch self {
        case .youtube: "play.rectangle"
        case .instagram: "camera"
        case .tiktok: "music.note"
        case .x: "at"
        case .bluesky: "cloud"
        case .mastodon: "bubble.left.and.bubble.right"
        }
    }

    /// Export networks go stale; Bluesky and Mastodon are read live.
    var isExport: Bool { self != .bluesky && self != .mastodon }

    /// Accounts there have a feed Sift can follow.
    var hasFeeds: Bool { self == .youtube || self == .bluesky || self == .mastodon }

    /// The folder new feeds from this network go in.
    var folder: String {
        switch self {
        case .youtube: "YouTube subscriptions"
        default: "\(name) follows"
        }
    }

    /// How to get a new export, for Settings and the monthly reminder.
    var exportSteps: String {
        switch self {
        case .youtube: "Go to takeout.google.com, select only \"YouTube and YouTube Music\" (subscriptions and playlists), and export once. Google emails a zip."
        case .instagram: "In Instagram, open Accounts Center > Your information and permissions > Download your information. Pick \"Followers and following\" and \"Saved\", format JSON. Instagram emails a link to the zip."
        case .tiktok: "In TikTok, open Settings and privacy > Account > Download your data. Pick JSON and request it. The zip shows under Download data when it is ready."
        case .x: "On x.com, open Settings > Your account > Download an archive of your data. X sends a link to the zip after a day or more."
        case .bluesky, .mastodon: ""
        }
    }
}

/// The person's choices for following lists, in state.json.
struct FollowingPrefs: Codable, Sendable, Equatable {
    /// The X archive (zip or folder) and the Google Takeout export.
    /// Instagram and TikTok use `instagramExportPath` and `tiktokExportPath`.
    var xArchivePath: String?
    var youtubeTakeoutPath: String?
    /// The person's own handles, for the public follow lists.
    var blueskyHandle = ""
    var mastodonHandle = ""
    /// Follow imported accounts that have a feed (YouTube, Bluesky, Mastodon).
    var followAsFeeds = true
    /// Watch ~/Downloads for new exports. Off until the person turns it on:
    /// macOS asks for access to Downloads.
    var watchDownloads = false
    /// Network id → when Sift last reminded the person to export again.
    var reminded: [String: Date] = [:]
    /// Place ids Sift followed as feeds once. An account you unfollow later
    /// is not followed again by the next import.
    var followed: [String] = []
    /// Downloads Sift imported: path → its file date, so one file imports once.
    var fromDownloads: [String: Date] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xArchivePath = try c.decodeIfPresent(String.self, forKey: .xArchivePath)
        youtubeTakeoutPath = try c.decodeIfPresent(String.self, forKey: .youtubeTakeoutPath)
        blueskyHandle = try c.decodeIfPresent(String.self, forKey: .blueskyHandle) ?? ""
        mastodonHandle = try c.decodeIfPresent(String.self, forKey: .mastodonHandle) ?? ""
        followAsFeeds = try c.decodeIfPresent(Bool.self, forKey: .followAsFeeds) ?? true
        watchDownloads = try c.decodeIfPresent(Bool.self, forKey: .watchDownloads) ?? false
        reminded = try c.decodeIfPresent([String: Date].self, forKey: .reminded) ?? [:]
        followed = try c.decodeIfPresent([String].self, forKey: .followed) ?? []
        fromDownloads = try c.decodeIfPresent([String: Date].self, forKey: .fromDownloads) ?? [:]
    }
}

/// One account the person follows.
struct FollowedAccount: Codable, Hashable, Sendable, Identifiable {
    var place: Place
    var name: String
    /// When the person followed it, if the export says.
    var since: Date?
    /// The feed to follow, for networks that have one.
    var feedURL: String?
    var id: String { place.id }
}

/// What Sift read from one network.
struct NetworkFollows: Codable, Sendable {
    var accounts: [FollowedAccount] = []
    /// When the export was made (file date), nil for Bluesky and Mastodon.
    var exportDate: Date?
    /// The newest follow date in the data, when the export has dates.
    var newest: Date?
    /// When Sift read it.
    var read: Date
    /// The export path or handle it read, and its file date: a change
    /// makes Sift read again.
    var signature: String
    var error: String?

    /// The date the data reaches: the export's date, else the newest follow.
    var dataDate: Date? { exportDate ?? newest }
}

/// `Application Support/Sift/following.json`: network id → what Sift read.
/// It is rebuilt from the exports, so it is a plain file, not SafeStore.
enum FollowingStore {
    static var fileURL: URL { StateFile.url.deletingLastPathComponent().appending(path: "following.json") }

    static func load() -> [String: NetworkFollows] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? d.decode([String: NetworkFollows].self, from: data)) ?? [:]
    }

    static func save(_ all: [String: NetworkFollows]) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .prettyPrinted]
        if let data = try? e.encode(all) { try? data.write(to: fileURL, options: .atomic) }
    }
}

enum FollowingReader {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: YouTube Takeout

    /// `subscriptions.csv` in a Google Takeout zip or folder: Channel Id,
    /// Channel Url, Channel Title. Google translates the folder and the
    /// header, so rows count when the first column is a channel id.
    static func youtube(at path: String) throws -> [FollowedAccount] {
        var texts: [String] = []
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { throw Failure(message: "The Takeout export was not found at \(path).") }
        if isDir.boolValue {
            for f in ExportFile.files(in: path, where: { $0.contains("subscri") && $0.hasSuffix(".csv") }) {
                if let t = try? String(contentsOf: f, encoding: .utf8) { texts.append(t) }
            }
        } else {
            for m in ExportFile.members(path) where m.lowercased().contains("subscri") && m.lowercased().hasSuffix(".csv") {
                if let d = try ExportFile.unzip(path, member: m) { texts.append(String(decoding: d, as: UTF8.self)) }
            }
        }
        guard !texts.isEmpty else { throw Failure(message: "No subscriptions.csv in the Takeout. Export \"YouTube and YouTube Music\" with subscriptions included.") }
        var out: [FollowedAccount] = []
        var seen = Set<String>()
        for text in texts {
            for row in CSV.parse(text) {
                guard let id = row.first?.trimmingCharacters(in: .whitespaces),
                      id.range(of: #"^UC[\w-]{22}$"#, options: .regularExpression) != nil, seen.insert(id).inserted else { continue }
                let title = row.count > 2 ? row[2].trimmingCharacters(in: .whitespaces) : id
                // The same place People uses for a followed channel feed.
                let place = Place(platform: "youtube", url: "https://www.youtube.com/channel/\(id)", handle: id)
                out.append(FollowedAccount(place: place, name: title.isEmpty ? id : title, since: nil,
                                           feedURL: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"))
            }
        }
        return out
    }

    // MARK: Instagram

    /// `connections/followers_and_following/following.json` in the Instagram
    /// export: `relationships_following`, each with `string_list_data`
    /// (href, value = user name, timestamp). Newer exports put the user name
    /// in `title`; the href can be `/_u/<name>`.
    static func instagram(at path: String) throws -> [FollowedAccount] {
        guard let data = try ExportFile.data(at: path, folderPaths: ["connections/followers_and_following/following.json",
                                                                  "followers_and_following/following.json", "following.json"],
                                             zipMember: "*followers_and_following/following.json"),
              !data.isEmpty, let json = try? JSONSerialization.jsonObject(with: data) else {
            throw Failure(message: "No following.json in the Instagram export. Include \"Followers and following\", format JSON.")
        }
        let list = (json as? [String: Any])?["relationships_following"] as? [[String: Any]] ?? json as? [[String: Any]] ?? []
        var out: [FollowedAccount] = []
        var seen = Set<String>()
        for entry in list {
            let item = (entry["string_list_data"] as? [[String: Any]])?.first ?? [:]
            var user = (item["value"] as? String) ?? ""
            if user.isEmpty { user = (entry["title"] as? String) ?? "" }
            if user.isEmpty, let href = item["href"] as? String, let u = URL(string: href) {
                user = u.pathComponents.filter { $0 != "/" && $0 != "_u" }.last ?? ""
            }
            user = InstagramReader.fix(user).trimmingCharacters(in: .whitespaces)
            guard !user.isEmpty, seen.insert(user.lowercased()).inserted else { continue }
            let since = (item["timestamp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let place = Place(platform: "instagram", url: "https://www.instagram.com/\(user)/", handle: "@" + user)
            out.append(FollowedAccount(place: place, name: "@" + user, since: since))
        }
        return out
    }

    // MARK: TikTok

    /// The "Following" list in the TikTok export (under "Following List" in
    /// older exports): Date and UserName per entry, keys in any case.
    static func tiktok(at path: String) throws -> [FollowedAccount] {
        let json = try TikTokReader.read(path)
        var entries: [[String: Any]] = []
        TikTokReader.walk(json) { key, list in
            if ["following", "followinglist"].contains(key.lowercased().replacingOccurrences(of: " ", with: "")) { entries += list }
        }
        var out: [FollowedAccount] = []
        var seen = Set<String>()
        for e in entries {
            guard var user = TikTokReader.value(e, ["username", "uniqueid", "user"]) else { continue }
            if user.hasPrefix("@") { user.removeFirst() }
            guard !user.isEmpty, seen.insert(user.lowercased()).inserted else { continue }
            let place = Place(platform: "tiktok", url: "https://www.tiktok.com/@\(user)", handle: "@" + user)
            out.append(FollowedAccount(place: place, name: "@" + user, since: TikTokReader.value(e, ["date"]).flatMap(TikTokReader.parseDate)))
        }
        return out
    }

    // MARK: X

    /// `data/following.js` in the X archive: `window.YTD.following.part0 =
    /// [{"following": {"accountId", "userLink"}}]`. The archive gives no
    /// handle for a follow, so Sift takes handles from the mentions in your
    /// own posts (`data/tweets*.js`: screen_name with id_str). An account
    /// with no handle keeps its id ("x:#<id>") and opens as x.com/i/user/<id>.
    static func x(at path: String) throws -> [FollowedAccount] {
        guard let data = try ExportFile.data(at: path, folderPaths: ["data/following.js"], zipMember: "*data/following.js"),
              let list = ytd(data) else {
            throw Failure(message: "No data/following.js in the X archive. Use the zip X sends after Download an archive of your data.")
        }
        var handles: [String: (handle: String, name: String)] = [:]
        var tweetData: [Data] = []
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue {
            for f in ExportFile.files(in: path, where: { $0.contains("/data/tweet") && $0.hasSuffix(".js") }) {
                if let d = FileManager.default.contents(atPath: f.path(percentEncoded: false)) { tweetData.append(d) }
            }
        } else if let d = try? ExportFile.unzip(path, member: "*data/tweet*.js") {
            tweetData.append(d)
        }
        for d in tweetData { mentions(in: String(decoding: d, as: UTF8.self), into: &handles) }

        var out: [FollowedAccount] = []
        var seen = Set<String>()
        for entry in list {
            guard let f = entry["following"] as? [String: Any], let id = f["accountId"] as? String, seen.insert(id).inserted else { continue }
            if let h = handles[id] {
                out.append(FollowedAccount(place: Place(platform: "x", url: "https://x.com/\(h.handle)", handle: "@" + h.handle), name: h.name))
            } else {
                out.append(FollowedAccount(place: Place(platform: "x", url: "https://x.com/i/user/\(id)", handle: "#" + id), name: "X account \(id)"))
            }
        }
        return out
    }

    /// The array after the `=` in an X archive `.js` file.
    static func ytd(_ data: Data) -> [[String: Any]]? {
        let text = String(decoding: data, as: UTF8.self)
        guard let eq = text.firstIndex(of: "="), let start = text[eq...].firstIndex(of: "[") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) as? [[String: Any]]
    }

    private static let mention = try! NSRegularExpression(
        pattern: #""name"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"screen_name"\s*:\s*"(\w{1,15})"[^{}]*?"id_str"\s*:\s*"(\d+)""#)

    private static func mentions(in text: String, into out: inout [String: (handle: String, name: String)]) {
        let ns = text as NSString
        for m in mention.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: m.range(at: 3))
            guard out[id] == nil else { continue }
            let raw = ns.substring(with: m.range(at: 1))
            let name = (try? JSONSerialization.jsonObject(with: Data("\"\(raw)\"".utf8), options: .fragmentsAllowed) as? String) ?? raw
            out[id] = (ns.substring(with: m.range(at: 2)), name)
        }
    }

    // MARK: Bluesky and Mastodon (public APIs, no login)

    /// Most accounts read per network: 20 pages of 100 on Bluesky, 25 of 80
    /// on Mastodon.
    static let maxAccounts = 2_000

    /// Who `handle` follows on Bluesky, through the public AppView.
    static func bluesky(handle: String) async throws -> [FollowedAccount] {
        let actor = handle.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !actor.isEmpty, let q = actor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw Failure(message: "Type your Bluesky handle, like @name.bsky.social.") }
        var out: [FollowedAccount] = []
        var cursor: String?
        repeat {
            var url = "https://public.api.bsky.app/xrpc/app.bsky.graph.getFollows?actor=\(q)&limit=100"
            if let c = cursor?.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { url += "&cursor=\(c)" }
            guard let u = URL(string: url), let (json, _) = await get(u), let obj = json as? [String: Any],
                  let list = obj["follows"] as? [[String: Any]] else {
                if out.isEmpty { throw Failure(message: "Bluesky did not answer for @\(actor). Check the handle.") }
                break
            }
            for s in list {
                guard let h = (s["handle"] as? String)?.lowercased(), h != "handle.invalid" else { continue }
                let name = (s["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "@" + h
                out.append(FollowedAccount(place: Place(platform: "bluesky", url: "https://bsky.app/profile/\(h)", handle: "@" + h),
                                           name: name, feedURL: "https://bsky.app/profile/\(h)/rss"))
            }
            cursor = obj["cursor"] as? String
        } while cursor != nil && out.count < maxAccounts
        return out
    }

    /// Who "@user@instance" follows on Mastodon: accounts/lookup, then
    /// accounts/<id>/following, page by page through the Link header.
    static func mastodon(handle: String) async throws -> [FollowedAccount] {
        let bits = handle.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).split(separator: "@")
        guard bits.count == 2, let user = bits[0].addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw Failure(message: "Type your Mastodon handle with its server, like @name@mastodon.social.")
        }
        let host = String(bits[1]).lowercased()
        guard let lookup = URL(string: "https://\(host)/api/v1/accounts/lookup?acct=\(user)"),
              let (json, _) = await get(lookup), let id = (json as? [String: Any])?["id"] as? String else {
            throw Failure(message: "\(host) did not find @\(bits[0]). Check the handle.")
        }
        var out: [FollowedAccount] = []
        var next = URL(string: "https://\(host)/api/v1/accounts/\(id)/following?limit=80")
        while let page = next, out.count < maxAccounts, let (json, link) = await get(page), let list = json as? [[String: Any]] {
            for a in list {
                guard let acct = a["acct"] as? String, let profile = a["url"] as? String, let u = URL(string: profile),
                      let h = u.host()?.lowercased() else { continue }
                let full = acct.contains("@") ? acct : acct + "@" + host
                let name = (a["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "@" + full
                // Mastodon profiles are /@user; their RSS is /@user.rss.
                let parts = u.pathComponents.filter { $0 != "/" }
                let feed = parts.count == 1 && parts[0].hasPrefix("@") ? "https://\(h)/\(parts[0]).rss" : nil
                // The handle People uses: "@user@<profile host>".
                let local = full.split(separator: "@").first.map(String.init) ?? full
                out.append(FollowedAccount(place: Place(platform: "mastodon", url: profile, handle: "@\(local)@\(h)"), name: name, feedURL: feed))
            }
            next = link
        }
        return out
    }

    /// One JSON page through HostGate, with the Link header's rel="next".
    private static func get(_ url: URL) async -> (Any, URL?)? {
        guard !Demo.isOn, let host = url.host() else { return nil }
        guard await HostGate.shared.admit(host) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: req), let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 429 || http.statusCode == 503 { await HostGate.shared.pause(host, seconds: 3600) }
        guard (200..<300).contains(http.statusCode), let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var next: URL?
        if let link = http.value(forHTTPHeaderField: "Link"),
           let r = link.range(of: #"<([^>]+)>;\s*rel="next""#, options: .regularExpression) {
            next = URL(string: String(link[r]).components(separatedBy: ">").first.map { String($0.dropFirst()) } ?? "")
        }
        return (json, next)
    }

    // MARK: Recognising exports (Downloads watcher, issue #43)

    /// Which export a zip is, from its member names (`ExportFile.members`).
    /// A TikTok JSON file is known by its name ("user_data_tiktok.json").
    static func kind(members raw: [String]) -> FollowNetwork? {
        let members = raw.map { $0.lowercased() }
        if members.contains(where: { $0.hasSuffix("data/following.js") || $0.hasSuffix("data/manifest.js") || $0.hasSuffix("data/tweets.js") }) { return .x }
        if members.contains(where: { $0.hasPrefix("your_instagram_activity/") || $0.contains("followers_and_following/") || $0.hasPrefix("personal_information/personal_information") }) { return .instagram }
        if members.contains(where: { $0.hasSuffix("user_data_tiktok.json") || $0.hasSuffix("user_data.json") }) { return .tiktok }
        if members.contains(where: { $0.hasPrefix("takeout/") && $0.contains("youtube") && $0.hasSuffix(".csv") }) { return .youtube }
        return nil
    }
}
