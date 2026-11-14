import Foundation

/// Transactional tabs: pages open for a task, not out of curiosity. Orders,
/// accounts, logins, carts, dashboards, searches, maps, mail, documents being
/// edited. They go to the "errands" bucket, stay out of themes, the graph and
/// exports, and never go to Claude for theme discovery.
///
/// This catches the clear cases by URL. Claude catches the rest during theme
/// discovery and sorting (the "errand" kind and the errands bucket).
enum Errands {
    private static let hostPrefixes = ["accounts.", "login.", "auth.", "signin.", "checkout.", "pay.", "billing.",
                                       "dashboard.", "console.", "admin.", "app.", "my.", "mail.", "calendar."]
    private static let hosts: Set<String> = [
        "mail.google.com", "calendar.google.com", "drive.google.com", "docs.google.com", "meet.google.com",
        "maps.google.com", "translate.google.com", "maps.apple.com", "outlook.live.com", "outlook.office.com",
        "localhost", "127.0.0.1", "vercel.com", "dash.cloudflare.com", "dashboard.stripe.com", "appstoreconnect.apple.com",
        "developer.apple.com", "icloud.com", "web.whatsapp.com", "app.slack.com", "linear.app", "notion.so",
        "chill.institute", "put.io",
    ]
    private static let searchHosts: Set<String> = ["google.com", "bing.com", "duckduckgo.com", "search.yahoo.com", "search.brave.com", "kagi.com"]
    private static let pathWords = ["/order", "/orders", "/account", "/checkout", "/cart", "/basket", "/login", "/signin",
                                    "/sign-in", "/signup", "/register", "/billing", "/invoice", "/settings", "/dashboard",
                                    "/admin", "/track", "/tracking", "/booking", "/reservation", "/subscription", "/payment",
                                    "/compose", "/inbox", "/edit"]

    static func isErrand(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let rawHost = url.host()?.lowercased() else { return false }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if hosts.contains(host) { return true }
        if hostPrefixes.contains(where: { host.hasPrefix($0) }) { return true }
        if host.hasSuffix(".starlings.work") && url.path().hasPrefix("/work") { return true }
        let path = url.path().lowercased()
        if searchHosts.contains(host) && (path.hasPrefix("/search") || url.query()?.contains("q=") == true) { return true }
        if host.hasSuffix("google.com") && path.hasPrefix("/search") { return true }
        if host == "github.com" && (path.contains("/pull/") || path.contains("/settings") || path.hasSuffix("/new")) { return true }
        if pathWords.contains(where: { path == $0 || path.hasPrefix($0 + "/") || path.contains($0 + "/") || path.hasSuffix($0) }) { return true }
        return false
    }
}
