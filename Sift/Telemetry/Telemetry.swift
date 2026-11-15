import CryptoKit
import Foundation
import Security

/// Anonymous diagnostics: one aggregate batch per Mac per ISO week.
///
/// Ported from Headroom's telemetry (same contract, same Worker shape). It is
/// on by default and has one switch, in Settings > Privacy. It never sends a
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
    /// instagram, x, import.
    let sources: [String]
    /// Kinds of destination set up: starlings, obsidian, markdown, reading-list.
    let destinations: [String]
    /// The sorting backend: claude-code or api.
    let backend: String
    let scale: Scale
    let features: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case schema
        case batchID = "batch_id"
        case dedupeKey = "dedupe_key"
        case period, cohort, app, sources, destinations, backend, scale, features
    }
}

enum Telemetry {
    static let enabledKey = "telemetryEnabled"
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
        switch id {
        case ReadingListReader.sourceID: return "reading-list"
        case InstagramReader.sourceID: return "instagram"
        case AppModel.xBookmarksSourceID: return "x"
        default: return nil
        }
    }

    static let destinationKinds: Set<String> = ["starlings", "obsidian", "markdown", "reading-list"]

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
        return TelemetryBatch(
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
