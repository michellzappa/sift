import Foundation

/// Open Graph preview for cards the Mac sent without a picture: fetches the
/// page once on the phone, reads og:image / twitter:image and og:description,
/// and keeps the result in Documents/og.json. One request at a time, so no
/// site gets a burst. X is skipped: its page has no preview tags without
/// JavaScript, and Sift keeps X's unofficial image endpoint opt-in.
actor OpenGraph {
    static let shared = OpenGraph()

    struct Preview: Codable, Sendable {
        var image: String?
        var description: String?
    }

    private var cache: [String: Preview] = [:]
    private var loaded = false
    private var inFlight: [String: Task<Preview, Never>] = [:]
    private var dirty = false

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "og.json")
    }

    func preview(for url: String) async -> Preview? {
        if !loaded {
            loaded = true
            if let data = try? Data(contentsOf: fileURL),
               let saved = try? JSONDecoder().decode([String: Preview].self, from: data) { cache = saved }
        }
        if let hit = cache[url] { return hit }
        guard let u = URL(string: url), let host = u.host(), !Self.skipped(host) else { return nil }
        if let running = inFlight[url] { return await running.value }
        let task = Task { await Self.fetch(u) }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        cache[url] = result
        save()
        return result
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: fileURL, options: .atomic) }
    }

    static func skipped(_ host: String) -> Bool {
        ["x.com", "twitter.com", "mobile.twitter.com"].contains(host.replacingOccurrences(of: "www.", with: ""))
    }

    private static func fetch(_ url: URL) async -> Preview {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) ?? false else { return Preview() }
        // The tags are in <head>: the first 300 KB are enough.
        let html = String(decoding: data.prefix(300_000), as: UTF8.self)
        func meta(_ keys: [String]) -> String? {
            for key in keys {
                let patterns = [
                    #"<meta[^>]+(?:property|name)=["']\#(key)["'][^>]+content=["']([^"']+)["']"#,
                    #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']\#(key)["']"#,
                ]
                for p in patterns {
                    if let r = html.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                        let tag = String(html[r])
                        if let c = tag.range(of: #"content=["']([^"']+)["']"#, options: .regularExpression) {
                            let value = tag[c].dropFirst(9).dropLast()
                            return String(value).replacingOccurrences(of: "&amp;", with: "&")
                        }
                    }
                }
            }
            return nil
        }
        var image = meta(["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"])
        if let i = image, i.hasPrefix("//") { image = "https:" + i }
        if let i = image, i.hasPrefix("/") { image = URL(string: i, relativeTo: url)?.absoluteString }
        return Preview(image: image?.hasPrefix("http") == true ? image : nil,
                       description: meta(["og:description", "twitter:description", "description"]))
    }
}
