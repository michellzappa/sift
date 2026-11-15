import AppKit
import Foundation
import SwiftUI

/// Demo mode: Sift with made-up sample data, for README screenshots and for
/// trying the app without your own links.
///
/// Start Sift with the launch argument `-demo` (or `SIFT_DEMO=1`). Then:
///
/// - Every Sift data file lives in ~/Library/Application Support/Sift-Demo,
///   never in Sift. All paths derive from `StateFile.url`, which asks
///   `Demo.folder`. Safari's tab database, the Reading List plist and the
///   iPhone close list point into Sift-Demo too.
/// - On launch, Sift-Demo is replaced with the sample data from the app
///   bundle (`Demo/` in the repo), so every run starts the same.
/// - Nothing touches the network or the owner's accounts: no previews,
///   capture, transcripts, images, Claude, on-device model, Starlings, X or
///   Chrome helper. The keychain reads as empty. Sending records a sent
///   link without calling a sender.
/// - `-demoView` picks the first view, for scripts/screenshots.sh.
enum Demo {
    static let isOn: Bool = {
        let p = ProcessInfo.processInfo
        return p.arguments.contains("-demo") || p.environment["SIFT_DEMO"] == "1"
    }()

    /// ~/Library/Application Support/Sift-Demo. The first use installs the
    /// sample data, so it is there before any file loads.
    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Sift-Demo", directoryHint: .isDirectory)
        install(into: dir)
        return dir
    }()

    /// Shown when a button would call Claude or a service.
    static let offMessage = "Demo mode uses sample data only. It does not call Claude or any service."

    // MARK: Install

    /// Replaces the folder with the bundle's sample data. The JSON files
    /// carry {{DEMO_PATH}} and {{DEMO_URL}} where a path or file URL into
    /// the folder goes (images, the Instagram export, the YouTube import).
    private static func install(into dir: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        if let source = Bundle.main.url(forResource: "Demo", withExtension: nil) {
            try? fm.copyItem(at: source, to: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.path(percentEncoded: false).replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        let url = dir.absoluteString.replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        if let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let file as URL in walker where file.pathExtension == "json" {
                guard let text = try? String(contentsOf: file, encoding: .utf8), text.contains("{{DEMO_") else { continue }
                let out = text.replacingOccurrences(of: "{{DEMO_PATH}}", with: path).replacingOccurrences(of: "{{DEMO_URL}}", with: url)
                try? out.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        // Stand-ins for the optional transcript tools, so Settings shows them
        // as installed. Demo mode never runs them; if run, they exit 1.
        let bin = dir.appending(path: "tools/venv/bin", directoryHint: .isDirectory)
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["youtube_transcript_api", "yt-dlp"] {
            let file = bin.appending(path: name)
            try? "#!/bin/sh\nexit 1\n".write(to: file, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        }
    }

    // MARK: Network

    /// Called once from AppModel.init in demo mode. Every http and https
    /// request through URLSession.shared (AsyncImage included) fails, as a
    /// second line behind the guards in each job.
    static func start() {
        URLProtocol.registerClass(NoNetwork.self)
    }

    final class NoNetwork: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            let scheme = request.url?.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }

    // MARK: Launch arguments for screenshots

    /// The view to open: `-demoView graph | theme:<name> | list:<source> |
    /// settings:<tab>`. Sources: iphone, mac, reading-list, instagram, x,
    /// youtube, or a source id.
    enum StartView: Equatable {
        case graph
        case theme(String)
        case list(String)
        case settings(String)
    }

    @MainActor
    static var startView: StartView? {
        guard isOn, let raw = argument("-demoView") else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "graph": return .graph
        case "theme": return .theme(value)
        case "list": return .list(sourceID(value))
        case "settings": return .settings(value.isEmpty ? "inputs" : value)
        default: return nil
        }
    }

    /// The Settings tab to open first: inputs, library, outputs, intelligence, themes, privacy.
    @MainActor
    static var settingsTab: String? {
        if case .settings(let tab) = startView { return tab }
        return nil
    }

    /// Sample source ids, by short name.
    @MainActor
    static func sourceID(_ alias: String) -> String {
        switch alias {
        case "iphone": "demo-iphone"
        case "mac": "demo-studio-mac"
        case "reading-list": ReadingListReader.sourceID
        case "instagram": InstagramReader.sourceID
        case "x": AppModel.xBookmarksSourceID
        case "youtube": LinkImporter.sourcePrefix + "demo-youtube"
        default: alias
        }
    }

    /// `-demoSize 1440x900`: the main window's content size.
    static var windowSize: NSSize? {
        guard isOn, let raw = argument("-demoSize") else { return nil }
        let n = raw.lowercased().split(separator: "x").compactMap { Double($0) }
        return n.count == 2 ? NSSize(width: n[0], height: n[1]) : nil
    }

    /// `-demoAppearance light | dark`.
    @MainActor
    static func applyAppearance() {
        guard isOn, let raw = argument("-demoAppearance") else { return }
        NSApp.appearance = NSAppearance(named: raw.lowercased() == "dark" ? .darkAqua : .aqua)
    }

    @MainActor
    static func sizeMainWindow() {
        guard let size = windowSize,
              let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.identifier?.rawValue != "com_apple_SwiftUI_Settings_window" })
        else { return }
        window.setContentSize(size)
        window.center()
    }

    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}

/// A small mark in the sidebar so demo data is never taken for real data.
struct DemoBadge: View {
    var body: some View {
        if Demo.isOn {
            Text("Demo data")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
                .foregroundStyle(.orange)
                .help("Sift runs on made-up sample data in ~/Library/Application Support/Sift-Demo. Nothing goes to the network.")
        }
    }
}
