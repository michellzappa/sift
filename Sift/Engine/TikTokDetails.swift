import CryptoKit
import Foundation

/// Caption, author and cover of a public TikTok video, from the video's own
/// page: TikTok puts them in a JSON script (`__UNIVERSAL_DATA_FOR_REHYDRATION__`)
/// that loads without a login or JavaScript. TikTok's oEmbed no longer
/// returns a title or thumbnail. One request per video, paced by `HostGate`.
/// The cover is saved on this Mac, because TikTok's image links expire.
enum TikTokPage {
    struct Details: Sendable {
        var author: String
        var username: String
        var caption: String
        var seconds: Int?
        var cover: String?
    }

    enum Outcome: Sendable { case details(Details), gone, throttled }

    static let gate = "www.tiktok.com"

    static func fetch(_ url: String) async -> Outcome {
        guard let id = TikTokReader.videoID(url), let page = URL(string: "https://www.tiktok.com/@/video/\(id)") else { return .gone }
        guard await HostGate.shared.admit(gate) else { return .throttled }
        var request = URLRequest(url: page, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .throttled }
        if http.statusCode == 429 || http.statusCode == 503 {
            await HostGate.shared.pause(gate, seconds: 3600)
            return .throttled
        }
        if http.statusCode == 404 || http.statusCode == 410 { return .gone }
        let html = String(decoding: data, as: UTF8.self)
        // A page without the data script is a check page, not the video: wait.
        guard let r = html.range(of: #"<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">"#),
              let end = html.range(of: "</script>", range: r.upperBound..<html.endIndex),
              let json = try? JSONSerialization.jsonObject(with: Data(html[r.upperBound..<end.lowerBound].utf8)) as? [String: Any]
        else {
            await HostGate.shared.pause(gate, seconds: 3600)
            return .throttled
        }
        let scope = (json["__DEFAULT_SCOPE__"] as? [String: Any])?["webapp.video-detail"] as? [String: Any]
        // Deleted or private videos have a status code and no item.
        guard let item = (scope?["itemInfo"] as? [String: Any])?["itemStruct"] as? [String: Any] else { return .gone }
        let author = item["author"] as? [String: Any] ?? [:]
        let video = item["video"] as? [String: Any] ?? [:]
        var details = Details(author: author["nickname"] as? String ?? "",
                              username: author["uniqueId"] as? String ?? "",
                              caption: item["desc"] as? String ?? "",
                              seconds: (video["duration"] as? NSNumber)?.intValue)
        if let cover = (video["cover"] as? String) ?? (video["originCover"] as? String) {
            details.cover = await saveCover(cover, for: url)
        }
        return .details(details)
    }

    /// Saves the cover next to the Instagram images. Returns a file URL.
    private static func saveCover(_ src: String, for url: String) async -> String? {
        let name = Insecure.SHA1.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16) + ".jpg"
        let dir = StateFile.url.deletingLastPathComponent().appending(path: "Images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: name)
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { return file.absoluteString }
        guard let remote = URL(string: src),
              let (data, response) = try? await URLSession.shared.data(from: remote),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 else { return nil }
        try? data.write(to: file, options: .atomic)
        return file.absoluteString
    }
}
