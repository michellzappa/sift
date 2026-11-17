import CryptoKit
import Foundation
import Security

/// Anonymous diagnostics: one aggregate batch per Mac per ISO week.
///
/// Ported from Headroom's telemetry (same contract, same Worker shape). It is
/// on by default and has one switch, in Settings > Telemetry. It never sends a
/// link, title, theme name, note, file path, account or token, only the
/// counts and switches in `TelemetryBatch`. Settings shows the exact batch.
/// docs/telemetry.md is the privacy contract; `telemetry/` is the Worker.
struct TelemetryBatch: Codable, Equatable, Sendable {
    struct App: Codable, Equatable, Sendable {
        let version: String
        let build: String
        let macOSMajor: Int
        let architecture: String

        enum CodingKeys: String, CodingKey {
            case version, build
            case macOSMajor = "macos_major"
            case architecture
        }
    }

    struct Scale: Codable, Equatable, Sendable {
        /// Saved links, as a bucket ("100-999"), never the count.
        let links: String
        /// Themes, as a bucket ("5-9").
        let themes: String
    }

    let schema: Int
    let batchID: String
    /// HMAC-SHA256(install secret, period), 64 lowercase hex characters. It
    /// changes every ISO week, so the server can drop a second report from
    /// the same Mac in the same week without getting an install id.
    let dedupeKey: String
    let period: String
    /// `new`, `returning` or `reactivated`, worked out on this Mac from the
    /// last week it reported. It carries no identity.
    let cohort: String
    let app: App
    /// Kinds of source with at least one link: safari, chrome, reading-list,
    /// instagram, tiktok, x, import, feed.
    let sources: [String]
    /// Kinds of destination set up: starlings, obsidian, markdown, reading-list.
    let destinations: [String]
    /// The sorting backend: claude-code or api.
    let backend: String
    let scale: Scale
    let features: [String: Bool]
    /// Kinds of feed followed (`FeedProvider` ids, "web" for the rest), no
    /// addresses or names.
    var feedKinds: [String]? = nil
    /// Ids from the Worker's public list of well-known feeds that this Mac
    /// follows. Only feeds on that list; any other feed never leaves the Mac.
    /// Nil when the Known Feeds switch is off.
    var knownFeeds: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case schema
        case batchID = "batch_id"
        case dedupeKey = "dedupe_key"
        case period, cohort, app, sources, destinations, backend, scale, features
        case feedKinds = "feed_kinds"
        case knownFeeds = "known_feeds"
    }
}

enum Telemetry {
    static let enabledKey = "telemetryEnabled"
    static let knownFeedsKey = "telemetryKnownFeeds"
    static let lastSubmittedPeriodKey = "telemetryLastSubmittedPeriod"
    static let endpointKey = "telemetryEndpoint"
    static let schemaVersion = 1
    static let defaultEndpoint = "https://sift-telemetry.envisioning.workers.dev/v1/batches"
    static let communityURL = URL(string: "https://sift-telemetry.envisioning.workers.dev/community")!
    static let contractURL = URL(string: "https://github.com/michellzappa/sift/blob/main/docs/telemetry.md")!

    private static let secretService = "app.sift.telemetry"

    /// On unless the user turned it off. Never in demo mode.
    static var enabled: Bool {
        guard !Demo.isOn else { return false }
        return (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true
    }

    /// Well-known feed ids in the report: on by default (owner, 2026-11-15),
    /// and only while the usage counts are on.
    static var knownFeedsEnabled: Bool {
        enabled && ((UserDefaults.standard.object(forKey: knownFeedsKey) as? Bool) ?? true)
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
        // The install secret stays: a new one would let an off-and-on count
        // the same Mac twice in a week.
        if !on { try? FileManager.default.removeItem(at: pendingURL) }
    }

    static var endpoint: URL? {
        let raw = UserDefaults.standard.string(forKey: endpointKey) ?? defaultEndpoint
        guard let url = URL(string: raw), url.scheme == "https" || url.host == "127.0.0.1" else { return nil }
        return url
    }

    // MARK: Files (under Application Support/Sift/telemetry)

    static var folder: URL {
        StateFile.url.deletingLastPathComponent().appending(path: "telemetry", directoryHint: .isDirectory)
    }
    static var pendingURL: URL { folder.appending(path: "pending.json") }
    static var secretURL: URL { folder.appending(path: "install_secret") }

    static var knownFeedsURL: URL { folder.appending(path: "known_feeds.json") }

    static func loadPending() -> TelemetryBatch? {
        guard enabled, let data = try? Data(contentsOf: pendingURL) else { return nil }
        return try? JSONDecoder().decode(TelemetryBatch.self, from: data)
    }

    static func savePending(_ batch: TelemetryBatch) {
        guard enabled, let data = try? JSONEncoder().encode(batch) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: pendingURL, options: .atomic)
    }

    // MARK: Weeks and cohorts

    static func period(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    /// The ISO week before `period`, through the calendar so W01 resolves to
    /// W52 or W53 of the year before.
    static func previousPeriod(of period: String) -> String? {
        guard period.count == 8, let year = Int(period.prefix(4)), let week = Int(period.suffix(2)) else { return nil }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var c = DateComponents()
        c.yearForWeekOfYear = year
        c.weekOfYear = week
        c.weekday = calendar.firstWeekday
        guard let monday = calendar.date(from: c),
              let earlier = calendar.date(byAdding: .day, value: -7, to: monday) else { return nil }
        return self.period(earlier)
    }

    static func cohort(for period: String, lastSubmitted: String?) -> String {
        guard let lastSubmitted, !lastSubmitted.isEmpty else { return "new" }
        if lastSubmitted == period || lastSubmitted == previousPeriod(of: period) { return "returning" }
        return "reactivated"
    }

    // MARK: Week key

    static func dedupeKey(period: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(period.utf8), using: SymmetricKey(data: installSecret()))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// 32 random bytes, in the login keychain and in a file, so Debug and
    /// Release builds on one Mac share a week key. It never leaves the Mac.
    static func installSecret() -> Data {
        if let hex = Keychain.read(service: secretService), let data = fromHex(hex) {
            writeSecretFile(hex)
            return data
        }
        if let hex = try? String(contentsOf: secretURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let data = fromHex(hex) {
            Keychain.save(hex, service: secretService)
            return data
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        Keychain.save(hex, service: secretService)
        writeSecretFile(hex)
        return Data(bytes)
    }

    private static func writeSecretFile(_ hex: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? Data(hex.utf8).write(to: secretURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretURL.path(percentEncoded: false))
    }

    private static func fromHex(_ hex: String) -> Data? {
        let s = hex.lowercased()
        guard s.count == 64, s.allSatisfy(\.isHexDigit) else { return nil }
        var data = Data(capacity: 32)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let byte = UInt8(s[i..<j], radix: 16) else { return nil }
            data.append(byte)
            i = j
        }
        return data
    }

    // MARK: Normalizing

    /// The kind of a source id. Device names, Chrome install ids and import
    /// names never leave the Mac.
    static func sourceKind(_ id: String) -> String? {
        if id.hasPrefix("tabs") || id.hasPrefix("demo-") { return "safari" }
        if id.hasPrefix(ChromeReader.sourcePrefix) { return "chrome" }
        if id.hasPrefix(LinkImporter.sourcePrefix) { return "import" }
        if id == TodayStore.keptSourceID { return "feed" }
        if id.hasPrefix(AppModel.listPrefix) { return "feed" }
        switch id {
        case ReadingListReader.sourceID: return "reading-list"
        case InstagramReader.sourceID: return "instagram"
        case TikTokReader.sourceID: return "tiktok"
        case AppModel.xBookmarksSourceID: return "x"
        default: return nil
        }
    }

    static let destinationKinds: Set<String> = ["starlings", "obsidian", "markdown", "reading-list"]

    /// The Worker's public list of well-known feeds (`/v1/feeds/known`). The
    /// request carries nothing about the Mac.
    struct KnownFeed: Codable, Sendable {
        let id: String
        let name: String
        let match: [String]
    }
    struct KnownFeedList: Codable, Sendable {
        let version: Int
        let feeds: [KnownFeed]
    }

    static var knownFeedsEndpoint: URL? {
        guard let batches = endpoint else { return nil }
        return batches.deletingLastPathComponent().appending(path: "feeds/known")
    }

    static func loadKnownFeeds() -> KnownFeedList? {
        guard let data = try? Data(contentsOf: knownFeedsURL) else { return nil }
        return try? JSONDecoder().decode(KnownFeedList.self, from: data)
    }

    /// Downloads the list, at most once a day; the copy on disk is used when
    /// the download fails.
    static func refreshKnownFeeds() async {
        let modified = (try? FileManager.default.attributesOfItem(atPath: knownFeedsURL.path(percentEncoded: false)))?[.modificationDate] as? Date
        if let modified, Date().timeIntervalSince(modified) < 24 * 60 * 60 { return }
        guard let url = knownFeedsEndpoint else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder().decode(KnownFeedList.self, from: data)) != nil else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: knownFeedsURL, options: .atomic)
    }

    /// The ids of `list` entries that one of `feeds` matches. A feed whose
    /// address looks like it carries a secret is never matched.
    static func knownFeedIDs(_ feeds: [Feed], list: KnownFeedList) -> [String] {
        let keys = feeds.compactMap { feedKey($0.url) }
        var ids = Set<String>()
        for entry in list.feeds where entry.match.contains(where: { pattern in keys.contains { matches($0, pattern) } }) {
            ids.insert(entry.id)
        }
        return ids.sorted()
    }

    /// "host/path", lowercase, without "www.", or nil for an address that
    /// looks private (a token, key or long random part).
    static func feedKey(_ raw: String) -> String? {
        guard let c = URLComponents(string: raw), var host = c.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let secretNames = ["token", "key", "auth", "uid", "secret", "sig", "password", "pass", "apikey", "access"]
        for item in c.queryItems ?? [] {
            let name = item.name.lowercased()
            if secretNames.contains(where: { name.contains($0) }) { return nil }
            if let value = item.value, looksRandom(value) { return nil }
        }
        if c.path.split(separator: "/").contains(where: { looksRandom(String($0)) }) { return nil }
        if c.user != nil || c.password != nil { return nil }
        var path = c.path.lowercased()
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    /// 20 or more letters and digits that mix both: a token, not a word.
    private static func looksRandom(_ s: String) -> Bool {
        guard s.count >= 20 else { return false }
        let alnum = s.filter { $0.isLetter || $0.isNumber }
        return alnum.count >= 20 && alnum.contains(where: \.isNumber) && alnum.contains(where: \.isLetter)
            && !s.contains("-") && !s.contains("_")
    }

    static func matches(_ key: String, _ pattern: String) -> Bool {
        let parts = pattern.split(separator: "/", maxSplits: 1)
        guard let phost = parts.first.map(String.init) else { return false }
        let ppath = parts.count > 1 ? "/" + parts[1] : ""
        let host = String(key.prefix { $0 != "/" })
        let path = String(key.dropFirst(host.count))
        guard host == phost || host.hasSuffix("." + phost) else { return false }
        if ppath.isEmpty || path == ppath { return true }
        guard path.hasPrefix(ppath), let next = path.dropFirst(ppath.count).first else { return false }
        return next == "/" || next == "."
    }

    static func bucket(_ n: Int, _ edges: [Int]) -> String {
        if n == 0 { return "0" }
        for (i, edge) in edges.enumerated() where n < edge {
            let low = i == 0 ? 1 : edges[i - 1]
            return "\(low)-\(edge - 1)"
        }
        return "\(edges.last ?? 0)+"
    }
}

/// Builds and sends the weekly batch. It checks on launch and every six
/// hours; a failed send is kept and tried again, and never shows an error.
@MainActor
final class TelemetryCoordinator {
    static let shared = TelemetryCoordinator()
    private var task: Task<Void, Never>?

    func start(_ model: AppModel) {
        guard task == nil, !Demo.isOn else { return }
        task = Task { [weak model] in
            // Let the first reload finish, so the counts are real.
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                if let model { await self.submitIfDue(model) }
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    private func submitIfDue(_ model: AppModel) async {
        guard Telemetry.enabled else { return }
        if let pending = Telemetry.loadPending() {
            if await send(pending) {
                try? FileManager.default.removeItem(at: Telemetry.pendingURL)
                UserDefaults.standard.set(pending.period, forKey: Telemetry.lastSubmittedPeriodKey)
            }
            return
        }
        let period = Telemetry.period()
        guard UserDefaults.standard.string(forKey: Telemetry.lastSubmittedPeriodKey) != period else { return }
        if Telemetry.knownFeedsEnabled { await Telemetry.refreshKnownFeeds() }
        let batch = makeBatch(model, period: period)
        if await send(batch) {
            UserDefaults.standard.set(period, forKey: Telemetry.lastSubmittedPeriodKey)
        } else {
            Telemetry.savePending(batch)
        }
    }

    /// The batch as it would go out now. Settings shows it.
    func preview(_ model: AppModel) -> TelemetryBatch {
        makeBatch(model, period: Telemetry.period())
    }

    private func makeBatch(_ model: AppModel, period: String) -> TelemetryBatch {
        let state = model.state
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        let sources = Set(model.archive.values.compactMap { Telemetry.sourceKind($0.source) }).sorted()
        let destinations = Set(state.destinations.map(\.kind)).intersection(Telemetry.destinationKinds).sorted()
        // Sources Sift is only trying (theme dials) are not follows.
        let feeds = state.feeds.filter { $0.enabled && $0.trial == nil }
        let feedKinds = Set(feeds.map { $0.provider ?? AppModel.providerID(forFeed: $0.url) ?? WebProvider.id }).sorted()
        var knownFeeds: [String]? = nil
        if Telemetry.knownFeedsEnabled, let list = Telemetry.loadKnownFeeds() {
            knownFeeds = Telemetry.knownFeedIDs(feeds, list: list)
        }
        var batch = TelemetryBatch(
            schema: Telemetry.schemaVersion,
            batchID: UUID().uuidString.lowercased(),
            dedupeKey: Telemetry.dedupeKey(period: period),
            period: period,
            cohort: Telemetry.cohort(for: period, lastSubmitted: UserDefaults.standard.string(forKey: Telemetry.lastSubmittedPeriodKey)),
            app: .init(
                version: info["CFBundleShortVersionString"] as? String ?? "0",
                build: info["CFBundleVersion"] as? String ?? "0",
                macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                architecture: architecture
            ),
            sources: sources,
            destinations: destinations,
            backend: state.backend == .api ? "api" : "claude-code",
            scale: .init(
                links: Telemetry.bucket(model.archive.count, [100, 1000, 10000]),
                themes: Telemetry.bucket(model.themes.count, [5, 10, 20])
            ),
            features: [
                "themes": !model.themes.isEmpty,
                "on_device_model": LocalModel.isAvailable,
                "local_first_pass": state.localFirstPass,
                "local_summaries": state.localSummaries,
                "youtube_transcripts": TranscriptTool.executable != nil,
                "reel_transcripts": ReelTool.executable != nil,
                "youtube_audio": state.youtubeAudio,
                "connections": state.findConnections,
                "close_after_send": state.closeAfterSend,
            ]
        )
        batch.feedKinds = feedKinds
        batch.knownFeeds = knownFeeds
        return batch
    }

    private func send(_ batch: TelemetryBatch) async -> Bool {
        guard Telemetry.enabled, let endpoint = Telemetry.endpoint,
              let body = try? JSONEncoder().encode(batch) else { return false }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
