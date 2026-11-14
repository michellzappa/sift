import AppKit
import Foundation

/// Sets up Chrome and other Chromium browsers to talk to Sift: a native
/// messaging host manifest per browser, and a copy of the extension the
/// user loads unpacked. Chrome Web Store publishing is not done; the fixed
/// `key` in ChromeExtension/manifest.json keeps the unpacked id stable.
enum ChromeHelper {
    /// The unpacked extension's id. It comes from the public key in
    /// ChromeExtension/manifest.json; change both together.
    static let extensionID = "olgmdjbjikcjaohhpmeekcmiknpfofpb"
    static let hostName = "app.sift.chrome"

    struct Browser: Hashable {
        let name: String
        /// Its folder in ~/Library/Application Support.
        let support: String
        let bundleID: String

        var folder: URL {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: support, directoryHint: .isDirectory)
        }
        var manifestURL: URL { folder.appending(path: "NativeMessagingHosts/\(ChromeHelper.hostName).json") }
    }

    static let browsers: [Browser] = [
        Browser(name: "Google Chrome", support: "Google/Chrome", bundleID: "com.google.Chrome"),
        Browser(name: "Chrome Beta", support: "Google/Chrome Beta", bundleID: "com.google.Chrome.beta"),
        Browser(name: "Chrome Dev", support: "Google/Chrome Dev", bundleID: "com.google.Chrome.dev"),
        Browser(name: "Chrome Canary", support: "Google/Chrome Canary", bundleID: "com.google.Chrome.canary"),
        Browser(name: "Chromium", support: "Chromium", bundleID: "org.chromium.Chromium"),
        Browser(name: "Brave", support: "BraveSoftware/Brave-Browser", bundleID: "com.brave.Browser"),
        Browser(name: "Microsoft Edge", support: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
        Browser(name: "Arc", support: "Arc/User Data", bundleID: "company.thebrowser.Browser"),
        Browser(name: "Vivaldi", support: "Vivaldi", bundleID: "com.vivaldi.Vivaldi"),
    ]

    /// Browsers that have run on this Mac (their Application Support folder exists).
    static var installedBrowsers: [Browser] {
        browsers.filter { FileManager.default.fileExists(atPath: $0.folder.path(percentEncoded: false)) }
    }

    /// The host Chrome starts: the copy in /Applications when there is one,
    /// else the one in the running app.
    static var hostURL: URL {
        let installed = URL(filePath: "/Applications/Sift.app/Contents/MacOS/sift-chrome")
        if FileManager.default.isExecutableFile(atPath: installed.path(percentEncoded: false)) { return installed }
        return Bundle.main.bundleURL.appending(path: "Contents/MacOS/sift-chrome")
    }

    /// Where the user loads the extension from. A copy outside the app, so
    /// the path stays the same when Sift updates.
    static var extensionFolder: URL {
        StateFile.url.deletingLastPathComponent().appending(path: "ChromeExtension", directoryHint: .isDirectory)
    }

    /// At least one browser has a host manifest that points at a host that exists.
    static var isInstalled: Bool {
        installedBrowsers.contains { b in
            guard let data = try? Data(contentsOf: b.manifestURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let path = json["path"] as? String else { return false }
            return FileManager.default.isExecutableFile(atPath: path)
        }
    }

    /// Writes the host manifest for each browser found and copies the
    /// extension. Returns the browsers it set up.
    static func install() throws -> [Browser] {
        let found = installedBrowsers
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Sift",
            "path": hostURL.path(percentEncoded: false),
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        for b in found {
            try FileManager.default.createDirectory(at: b.manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: b.manifestURL, options: .atomic)
        }
        try copyExtension()
        return found
    }

    /// Copies the bundled extension to `extensionFolder`, replacing an older copy.
    static func copyExtension() throws {
        guard let bundled = Bundle.main.url(forResource: "ChromeExtension", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let target = extensionFolder
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: bundled, to: target)
    }

    static func revealExtension() {
        if !FileManager.default.fileExists(atPath: extensionFolder.path(percentEncoded: false)) { try? copyExtension() }
        NSWorkspace.shared.activateFileViewerSelecting([extensionFolder])
    }

    /// Opens chrome://extensions in the first browser found.
    static func openExtensionsPage() {
        guard let page = URL(string: "chrome://extensions") else { return }
        for b in installedBrowsers {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.bundleID) else { continue }
            NSWorkspace.shared.open([page], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return
        }
    }
}
