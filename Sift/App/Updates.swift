import HouseKit
import AppKit
import Foundation
import Observation

/// Learning that a newer Sift exists, and handing the install to
/// `update-app.sh`. Ported from Headroom (docs/updater.md there).
///
/// The feed is GitHub's latest-release record for michellzappa/sift. It does
/// not have to be trusted: the script refuses any download whose checksum
/// does not match SHA256SUMS, that is not notarized, or that is not signed by
/// team 992N457T8D, which the script has compiled in.
enum UpdateCheck {
    static let feedURL = URL(string: "https://api.github.com/repos/michellzappa/sift/releases/latest")!

    static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Only the copy in /Applications updates itself. A build from Xcode, a
    /// worktree or the mini must never overwrite the installed app.
    static var canSelfUpdate: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path == "/Applications"
    }

    /// true when `a` is newer than `b`, by numeric parts (0.10.0 > 0.9.0).
    /// nil when either is not dotted numbers.
    static func isNewer(_ a: String, than b: String) -> Bool? {
        func parts(_ s: String) -> [Int]? {
            let p = s.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) }
            return p.contains(nil) || p.isEmpty ? nil : p.compactMap { $0 }
        }
        guard let x = parts(a), let y = parts(b) else { return nil }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Every field optional: a build that cannot read the record can never
    /// hear about an update again.
    struct Release: Decodable {
        var tagName: String?
        var draft: Bool?
        var prerelease: Bool?
        var body: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", draft, prerelease, body
        }
    }
}

/// Starts `Contents/Resources/update-app.sh` detached. The script quits Sift,
/// swaps the bundle and opens it again; its output goes to
/// Application Support/Sift/logs/update.log.
enum UpdateInstaller {
    static var scriptURL: URL? { Bundle.main.url(forResource: "update-app", withExtension: "sh") }

    static var logURL: URL {
        StateFile.url.deletingLastPathComponent().appending(path: "logs/update.log")
    }

    static func install(version: String) -> Bool {
        guard let script = scriptURL else { return false }
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sh")
        // nohup and &, so the script outlives the app it is about to quit.
        p.arguments = ["-c", #"nohup /bin/bash "$0" --yes --version "$1" >> "$2" 2>&1 &"#,
                       script.path(percentEncoded: false), version, logURL.path(percentEncoded: false)]
        return (try? p.run()) != nil
    }
}

@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let automaticKey = "automaticUpdateChecks"
    private static let interval: TimeInterval = 24 * 60 * 60

    /// A newer version that this copy can offer, or nil.
    private(set) var available: String?
    /// The newest version GitHub named on the last check.
    private(set) var latest: String?
    private(set) var lastChecked: Date?
    private(set) var lastError: String?
    private(set) var isChecking = false
    private var task: Task<Void, Never>?

    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticKey) }
    }

    /// Daily background check, the first one a minute after launch. Off in
    /// demo mode and for copies outside /Applications.
    func start() {
        guard task == nil, !Demo.isOn else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                guard let self else { return }
                if self.automatic, UpdateCheck.canSelfUpdate { await self.check() }
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    @discardableResult
    func check() async -> String? {
        guard !Demo.isOn else { lastError = Demo.offMessage; return nil }
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: UpdateCheck.feedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lastError = "GitHub answered \(http.statusCode)."
                return nil
            }
            let release = try JSONDecoder().decode(UpdateCheck.Release.self, from: data)
            lastChecked = Date()
            lastError = nil
            guard let tag = release.tagName, release.draft != true, release.prerelease != true else { return nil }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            latest = version
            available = UpdateCheck.isNewer(version, than: UpdateCheck.installedVersion) == true ? version : nil
            return available
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Hands the install to the script. Sift quits once the download is
    /// verified and opens again on the new version.
    func install() {
        guard let version = available else { return }
        guard UpdateCheck.canSelfUpdate else {
            NSWorkspace.shared.open(URL(string: "https://github.com/michellzappa/sift/releases/latest")!)
            return
        }
        if !UpdateInstaller.install(version: version) {
            lastError = "This build does not carry the updater."
        }
    }

    /// File > Check for Updates…: checks, then says what it found.
    func checkFromMenu() async {
        let found = await check()
        let alert = NSAlert()
        if let found {
            alert.messageText = "Sift \(found) is available"
            alert.informativeText = UpdateCheck.canSelfUpdate
                ? "You have \(UpdateCheck.installedVersion). Sift downloads and checks the new version, then quits and opens again."
                : "You have \(UpdateCheck.installedVersion). This copy is not in Applications, so it opens the release page."
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { install() }
        } else {
            alert.messageText = lastError == nil ? "Sift is up to date" : "Could not check for updates"
            alert.informativeText = lastError ?? "You have \(UpdateCheck.installedVersion), the latest version."
            alert.runModal()
        }
    }
}

/// The house Updates section (HouseKit `UpdatesSection`) reads Sift's checker
/// through this.
extension UpdateChecker: UpdateChecking {
    var installedVersion: String { UpdateCheck.installedVersion }
    var latestVersion: String? { latest }
    var availableVersion: String? { available }
    var automaticChecks: Bool {
        get { automatic }
        set { automatic = newValue }
    }
    var canInstall: Bool { UpdateCheck.canSelfUpdate }
    var policyNote: String {
        "Sift asks GitHub once a day. An update downloads, checks the checksum, Apple's notarization and the developer signature, then Sift quits and opens on the new version."
    }
    func checkForUpdates() async { await check() }
    func installUpdate() throws { install() }
}
