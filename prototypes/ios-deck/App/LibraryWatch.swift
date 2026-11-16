import SwiftUI

extension Item {
    /// The video a card can play: vertical (Shorts, Instagram, TikTok) or a
    /// wide YouTube video. Nil: Sift has no player for it.
    var playable: (video: VerticalVideo, wide: Bool)? {
        if let v = VerticalVideo.detect(self) { return (v, false) }
        if let id = TodayPick.youTubeID(url) { return (.youTube(id), true) }
        if let video, video.provider == "youtube" { return (.youTube(video.id), true) }
        return nil
    }
}

/// Library in the Watch tab (owner, 2026-11-16: "always have video"): your
/// saved videos as full cards with the player, like Today's Watch. YouTube
/// plays muted while on screen; Instagram and TikTok play on a tap. Unseen
/// first, in an order fixed when the tab opens, so a card does not jump
/// when it becomes seen. Playing or opening the text counts as seen;
/// scrolling past does not (a saved link stays until you watch it).
struct LibraryWatchView: View {
    @Environment(Store.self) private var store
    @Binding var part: ModePart
    @State private var position: String?
    @State private var reading: Item?
    @State private var order: [String] = []

    private var items: [Item] {
        var byURL: [String: Item] = [:]
        for item in store.deck.items where item.readingMode == .watch { byURL[item.url] = byURL[item.url] ?? item }
        return order.compactMap { byURL[$0] }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let items = items
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.url) { i, item in
                            card(item, current: (position ?? items.first?.url) == item.url)
                                .overlay(alignment: .topTrailing) {
                                    Text("\(i + 1)/\(items.count)")
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(10)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(item.url)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $position)
                .scrollIndicators(.hidden)
                .overlay {
                    if items.isEmpty {
                        ContentUnavailableView("No saved videos", systemImage: "play.rectangle",
                                               description: Text(store.deck.items.isEmpty
                                                                 ? "Import your library: Lists, then Log."
                                                                 : "Videos you save show here: YouTube, Instagram reels, TikTok."))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { PartPicker(part: $part) } }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .onAppear(perform: sortOnce)
            .onChange(of: store.deck.items.count) { _, _ in sortOnce() }
        }
    }

    private func card(_ item: Item, current: Bool) -> some View {
        PlayableCard(item: item, active: current, reason: item.theme,
                     played: { watched(item) }, text: { open(item) }) { seenDot(item) }
    }

    @ViewBuilder
    private func seenDot(_ item: Item) -> some View {
        if !store.isSeen(item.url) {
            Circle().fill(Color.accentColor).frame(width: 10, height: 10).padding(6)
        }
    }

    private func sortOnce() {
        var seen = Set<String>()
        let all = store.deck.items.filter { $0.readingMode == .watch && seen.insert($0.url).inserted }
        // Playable first, then unseen first.
        let ranked = all.sorted { a, b in
            let pa = a.playable != nil, pb = b.playable != nil
            if pa != pb { return pa }
            return !store.isSeen(a.url) && store.isSeen(b.url)
        }
        order = ranked.map(\.url)
    }

    private func watched(_ item: Item) {
        store.setSeen([item], true, mode: "library")
        store.record(item, .open, mode: "library", position: 0)
    }

    private func open(_ item: Item) {
        watched(item)
        reading = item
    }
}

/// Finds the video in a page that is not itself a video link (an article
/// with a YouTube or Vimeo player, a page with og:video or twitter:player),
/// so the card can play it (owner, 2026-11-16). One fetch per page; the
/// answer, a video or none, is kept in Documents/videos.json.
actor VideoFinder {
    static let shared = VideoFinder()

    private var cache: [String: String] = [:]
    private var loaded = false
    private var inFlight: [String: Task<String, Never>] = [:]

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "videos.json")
    }

    func video(in page: String) async -> VerticalVideo? {
        if !loaded {
            loaded = true
            if let data = try? Data(contentsOf: fileURL),
               let saved = try? JSONDecoder().decode([String: String].self, from: data) { cache = saved }
        }
        if let hit = cache[page] { return Self.video(from: hit) }
        guard let url = URL(string: page), url.scheme?.hasPrefix("http") == true,
              let host = url.host(), !OpenGraph.skipped(host) else { return nil }
        if let running = inFlight[page] { return Self.video(from: await running.value) }
        let task = Task { await Self.find(url) }
        inFlight[page] = task
        let found = await task.value
        inFlight[page] = nil
        cache[page] = found
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: fileURL, options: .atomic) }
        return Self.video(from: found)
    }

    /// A found address as a player: YouTube and Vimeo by id, a file by its
    /// extension, else an embeddable player page. "" is none.
    static func video(from found: String) -> VerticalVideo? {
        guard !found.isEmpty else { return nil }
        if let id = TodayPick.youTubeID(found) ?? embedID(found, #"youtube(?:-nocookie)?\.com/embed/([\w-]{11})"#) {
            return .youTube(id)
        }
        if let id = embedID(found, #"vimeo\.com/(?:video/)?(\d+)"#) { return .vimeo(id) }
        let path = URL(string: found)?.path().lowercased() ?? ""
        if [".mp4", ".m4v", ".mov", ".m3u8", ".webm"].contains(where: path.hasSuffix) { return .file(found) }
        return found.hasPrefix("https://") ? .embed(found) : nil
    }

    private static func embedID(_ s: String, _ pattern: String) -> String? {
        guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
        let m = String(s[r])
        guard let re = try? NSRegularExpression(pattern: pattern),
              let hit = re.firstMatch(in: m, range: NSRange(m.startIndex..., in: m)),
              let g = Range(hit.range(at: 1), in: m) else { return nil }
        return String(m[g])
    }

    private static func find(_ url: URL) async -> String {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) ?? false else { return "" }
        let html = String(decoding: data.prefix(800_000), as: UTF8.self)
        func first(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let g = Range(m.range(at: 1), in: html) else { return nil }
            var v = String(html[g]).replacingOccurrences(of: "&amp;", with: "&")
            if v.hasPrefix("//") { v = "https:" + v }
            if v.hasPrefix("/") { v = URL(string: v, relativeTo: url)?.absoluteString ?? v }
            return v
        }
        func meta(_ key: String) -> String? {
            first(#"<meta[^>]+(?:property|name)=["']"# + key + #"["'][^>]+content=["']([^"']+)["']"#)
                ?? first(#"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']"# + key + #"["']"#)
        }
        // A player in the page body first: it is the page's own video. Then
        // the tags the page gives for sharing.
        let candidates = [
            first(#"<iframe[^>]+src=["']([^"']*youtube(?:-nocookie)?\.com/embed/[\w-]{11}[^"']*)["']"#),
            first(#"<iframe[^>]+src=["']([^"']*player\.vimeo\.com/video/\d+[^"']*)["']"#),
            meta("og:video:secure_url"), meta("og:video:url"), meta("og:video"),
            meta("twitter:player"),
            first(#"<video[^>]+src=["']([^"']+)["']"#),
            first(#"<source[^>]+src=["']([^"']+\.(?:mp4|m3u8|webm)[^"']*)["']"#),
        ]
        for c in candidates.compactMap({ $0 }) where video(from: c) != nil { return c }
        return ""
    }
}

/// A card that plays the item's video: a known video link at once, else the
/// video found in the page (wide), else the usual card.
struct PlayableCard<Accessory: View>: View {
    let item: Item
    var vertical: Bool? = nil
    let active: Bool
    var reason: String? = nil
    var doubleTap: (() -> Void)? = nil
    var played: () -> Void = {}
    let text: () -> Void
    @ViewBuilder var accessory: () -> Accessory
    @State private var found: VerticalVideo?

    private var known: (video: VerticalVideo, wide: Bool)? {
        if let v = VerticalVideo.detect(item, vertical: vertical) { return (v, false) }
        return item.playable
    }

    var body: some View {
        if let p = known ?? found.map({ ($0, true) }) {
            VerticalVideoCard(item: item, video: p.video, active: active, doubleTap: doubleTap,
                              played: played, text: text, wide: p.wide, autoplay: true, reason: reason,
                              accessory: accessory)
        } else {
            CardView(item: item, tall: true, lede: true)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTap?() }
                .onTapGesture(perform: text)
                .overlay(alignment: .bottomTrailing) { accessory().padding(12) }
                .task(id: item.url) { found = await VideoFinder.shared.video(in: item.url) }
        }
    }
}
