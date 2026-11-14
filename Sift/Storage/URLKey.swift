import Foundation

/// One key per page, so the same link saved twice (from two sources, with
/// tracking parameters, as youtu.be or twitter.com) counts once.
enum URLKey {
    /// Query parameters that only track where a click came from.
    private static let tracking: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igsh", "igshid", "si", "ref", "ref_src",
        "ref_url", "s", "t", "feature", "share", "utm_id", "_ga", "cmpid", "smid", "smtyp",
    ]

    static func normalize(_ string: String) -> String {
        guard var c = URLComponents(string: string), var host = c.host?.lowercased() else { return string }
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) { host = String(host.dropFirst(prefix.count)) }
        if host == "twitter.com" { host = "x.com" }
        var path = c.path
        var items = c.queryItems ?? []
        if host == "youtu.be" {
            items = [URLQueryItem(name: "v", value: String(path.dropFirst()))]
            host = "youtube.com"; path = "/watch"
        }
        if host == "youtube.com" && path == "/watch" {
            items = items.filter { $0.name == "v" }
        } else if host == "instagram.com" || host == "x.com" {
            items = []
        } else {
            items = items.filter { !$0.name.lowercased().hasPrefix("utm_") && !tracking.contains($0.name.lowercased()) }
        }
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        c.scheme = "https"
        c.host = host
        c.path = path
        c.queryItems = items.isEmpty ? nil : items.sorted { $0.name < $1.name }
        c.fragment = nil
        c.port = nil
        return c.string ?? string
    }
}
