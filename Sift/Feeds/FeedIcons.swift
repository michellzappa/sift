import AppKit
import SwiftUI

/// Each feed's site icon, fetched once from the site itself (no icon
/// service): apple-touch-icon.png, else favicon.ico. Kept as PNG in
/// Application Support/Sift/feeds/icons/<feed id>.png and shown in grey
/// where a row has no picture, and beside the feed in the sidebar.
enum FeedIcons {
    static var folder: URL {
        let dir = FeedStore.folder.appending(path: "icons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(_ feedID: String) -> URL { folder.appending(path: "\(feedID).png") }

    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    /// The icon, if Sift has one for this feed.
    static func image(_ feedID: String) -> NSImage? {
        if let hit = cache.object(forKey: feedID as NSString) { return hit }
        guard let image = NSImage(contentsOf: file(feedID)) else { return nil }
        cache.setObject(image, forKey: feedID as NSString)
        return image
    }

    /// Fetches and saves the icon. False when the site has none Sift can read.
    static func fetch(_ feed: Feed) async -> Bool {
        guard !Demo.isOn, let base = URL(string: feed.site ?? feed.url), let host = base.host() else { return false }
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            guard let url = URL(string: "https://\(host)\(path)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200,
                  let image = NSImage(data: data), image.size.width >= 16,
                  let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: file(feed.id), options: .atomic)
            cache.removeObject(forKey: feed.id as NSString)
            return true
        }
        return false
    }
}

/// A feed's icon, or a symbol when there is none. Grey by default (the
/// sidebar); a list row shows it in colour while the item is unseen.
struct FeedIconView: View {
    let feedID: String
    var symbol = "dot.radiowaves.up.forward"
    var size: CGFloat = 16
    var grey = true

    var body: some View {
        if let image = FeedIcons.image(feedID) {
            Image(nsImage: image)
                .resizable().interpolation(.high).scaledToFit()
                .saturation(grey ? 0 : 1)
                .opacity(grey ? 0.75 : 1)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        } else {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}
