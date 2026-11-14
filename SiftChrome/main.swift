import Darwin
import Foundation

// sift-chrome: the native messaging host for Sift's Chrome extension. It
// ships inside Sift.app at Contents/MacOS/sift-chrome. Chrome starts it when
// the extension connects and stops it when the port closes.
//
// Transport (Chrome native messaging): each message is a 32-bit length in
// native byte order, then that many bytes of UTF-8 JSON, on stdin and
// stdout. Logs go to stderr. No network.
//
// For each snapshot the host writes
//   ~/Library/Application Support/Sift/chrome/tabs-<install>.json
// (atomic) and answers with the URLs from close.json in the same folder
// that are open in that snapshot.

enum Framing {
    /// Chrome sends at most 64 MiB to a host; a tab list is far smaller.
    static let maxIncoming = 16 << 20
    /// Chrome accepts at most 1 MiB from a host.
    static let maxOutgoing = 1 << 20

    static func read(_ handle: FileHandle = .standardInput) -> Data? {
        guard let header = exactly(4, from: handle) else { return nil }
        let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard length > 0, length <= maxIncoming else {
            Log.write("message of \(length) bytes refused")
            return nil
        }
        return exactly(length, from: handle)
    }

    static func write(_ object: [String: Any], to handle: FileHandle = .standardOutput) {
        guard JSONSerialization.isValidJSONObject(object),
              let body = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              body.count <= maxOutgoing
        else {
            Log.write("could not encode a reply")
            return
        }
        var length = UInt32(body.count).littleEndian
        var data = Data(bytes: &length, count: 4)
        data.append(body)
        handle.write(data)
    }

    private static func exactly(_ count: Int, from handle: FileHandle) -> Data? {
        var data = Data()
        while data.count < count {
            guard let chunk = try? handle.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
            data.append(chunk)
        }
        return data
    }
}

enum Log {
    static func write(_ text: String) {
        FileHandle.standardError.write(Data("[sift-chrome] \(text)\n".utf8))
    }
}

struct Tab: Codable, Equatable {
    var url: String
    var title: String
    var windowId: Int?
    var lastAccessed: Double?
    var pinned: Bool?
}

struct Incoming: Decodable {
    let type: String
    let install: String?
    let browser: String?
    let extensionVersion: String?
    let tabs: [Tab]?
}

/// The file Sift reads. Sift decodes the same keys (ChromeReader.Snapshot).
struct Snapshot: Codable {
    var version = 1
    var install: String
    var browser: String
    var extensionVersion: String
    var updated: Date
    var tabs: [Tab]
}

enum Store {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Sift/chrome", directoryHint: .isDirectory)
    }

    /// The install id becomes a file name: letters, digits and dashes only.
    static func validInstall(_ id: String?) -> String? {
        guard let id, (8...64).contains(id.count),
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" }),
              id.allSatisfy(\.isASCII)
        else { return nil }
        return id
    }

    static func write(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: folder.appending(path: "tabs-\(snapshot.install).json"), options: .atomic)
    }

    /// URLs Sift marked to close in Chrome: close.json, {"urls": [...]}.
    static func closeList() -> [String] {
        guard let data = try? Data(contentsOf: folder.appending(path: "close.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urls = object["urls"] as? [String]
        else { return [] }
        return urls
    }
}

/// The app that started this process ("Google Chrome", "Brave Browser"),
/// from the parent's executable path.
func parentAppName() -> String? {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let length = proc_pidpath(getppid(), &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    guard let app = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) else { return nil }
    return String(app.dropLast(4))
}

let parentApp = parentAppName()
var lastTabs: [Tab]?
var lastWrite = Date.distantPast

Log.write("ready (\(CommandLine.arguments.dropFirst().first ?? "no origin"))")
while let data = Framing.read() {
    guard let message = try? JSONDecoder().decode(Incoming.self, from: data) else {
        Framing.write(["type": "error", "message": "unreadable message"])
        continue
    }
    guard message.type == "snapshot" else {
        Framing.write(["type": "error", "message": "unknown type"])
        continue
    }
    guard let install = Store.validInstall(message.install) else {
        Framing.write(["type": "error", "message": "bad install id"])
        continue
    }
    let tabs = (message.tabs ?? []).prefix(20_000).compactMap { t -> Tab? in
        let scheme = t.url.prefix(8).lowercased()
        guard t.url.count <= 8192, scheme.hasPrefix("http://") || scheme.hasPrefix("https://") else { return nil }
        var tab = t
        tab.title = String(t.title.prefix(1000))
        return tab
    }
    // Rewrite when the tabs change, and at least hourly so Sift sees that
    // Chrome is still there.
    if tabs != lastTabs || Date().timeIntervalSince(lastWrite) > 3600 {
        let browser = parentApp ?? String((message.browser ?? "Chromium").prefix(60))
        let snapshot = Snapshot(install: install, browser: browser,
                                extensionVersion: String((message.extensionVersion ?? "").prefix(20)),
                                updated: .now, tabs: tabs)
        do {
            try Store.write(snapshot)
            lastTabs = tabs
            lastWrite = .now
        } catch {
            Log.write("could not write the snapshot: \(error.localizedDescription)")
        }
    }
    let open = Set(tabs.map(\.url))
    let close = Store.closeList().filter(open.contains).prefix(2000)
    Framing.write(["type": "close", "urls": Array(close)])
}
Log.write("stdin closed, exiting")
