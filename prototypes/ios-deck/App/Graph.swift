import SwiftUI

// Your Graph on the phone (owner, 2026-11-17). The Mac builds it
// (Sift/Feeds/Creators.swift) and writes iCloud Drive/Sift/Deck/creators.json;
// the phone shows it and asks for follows and hides through follows/, like
// the Feeds list. The Mac is the one that follows. Same shapes as the
// Mac's `writeCreatorsForPhone`.

struct CreatorsFile: Codable {
    struct Save: Codable, Hashable { var url, title: String; var date: Date; var theme: String? }
    struct Row: Codable, Identifiable, Hashable {
        var id, kind, name, input: String
        var count, recent: Int
        var score, bonus: Double
        var lastSaved: Date?
        var themes: [String: Int]
        var feedID: String?
        var hidden: Bool
        var saves: [Save]
        /// The Mac's graph rank (0…1) and the creators closest in meaning.
        var rank: Double?
        var closeTo: [String]?
        /// False for X, Instagram and TikTok authors: no feed, no Follow.
        /// Nil in files from older Macs (all creators had feeds then).
        var hasFeed: Bool?
        var canFollow: Bool { hasFeed ?? true }

        var symbol: String {
            switch kind {
            case "video": "play.rectangle"
            case "community": "bubble.left.and.bubble.right"
            case "code": "chevron.left.forwardslash.chevron.right"
            default: "doc.text"
            }
        }

        var topThemes: [(name: String, count: Int)] {
            themes.map { ($0.key, $0.value) }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        }
    }
    /// People: one person, every place they publish (the Mac's People).
    struct PlaceRow: Codable, Identifiable, Hashable {
        var id, platform, platformName, url, handle: String
        var hasFeed, followed: Bool
        /// What Follow takes on the Mac (`Place.followInput`).
        var input: String {
            switch platform {
            case "github": "https://github.com/" + handle.dropFirst() + ".atom"
            case "medium": "medium.com/" + handle
            case "youtube", "podcast": url
            default: handle
            }
        }
        var symbol: String {
            switch platform {
            case "youtube": "play.rectangle"
            case "podcast": "mic"
            case "github": "chevron.left.forwardslash.chevron.right"
            case "bluesky", "mastodon", "x", "threads": "bubble.left"
            case "instagram", "tiktok": "camera"
            case "substack", "medium": "envelope"
            default: "globe"
            }
        }
    }
    struct PersonRow: Codable, Identifiable, Hashable {
        var id, name: String
        var places: [PlaceRow]
        var evidence: [String]
    }
    /// Next Door: creators outside your graph that two or more of yours link to.
    struct Near: Codable, Identifiable, Hashable {
        struct Evidence: Codable, Hashable { var from, item, itemURL, link: String }
        var id, kind, name, input: String
        var linkedBy: [String]
        var mentions: Int
        var score: Double
        var themes: [String: Int]
        var evidence: [Evidence]

        /// "Linked by Dwarkesh Patel, Lenny's Podcast and 2 more · 9 links"
        var linkedText: String {
            let rest = linkedBy.count > 2 ? " and \(linkedBy.count - 2) more" : ""
            return "Linked by \(linkedBy.prefix(2).joined(separator: ", "))\(rest) · \(mentions) links"
        }
    }
    var schema: Int
    var halfLifeDays: Double
    var minSaves: Int
    var creators: [Row]
    var nextDoor: [Near]?
    /// Farther: Claude's suggestions per theme (the Mac's Feeds/Farther.swift).
    var farther: [String: FartherResult]?
    var fartherAsking: [String]?
    var people: [PersonRow]?
    /// The words that set each theme apart (the Mac's Subterms).
    var themeTerms: [String: [String]]?
    var directory: [DirectoryEntry]?
    var directoryBuilt: Date?
    /// Theme dials (the Mac's Engine/Dials.swift): theme → leanIn or explore.
    var dials: [String: String]?
    /// Sources the Mac is trying for a theme set to Lean In or Explore.
    var trials: [TrialRow]?
    struct TrialRow: Codable, Identifiable, Hashable {
        var feedID, title, url, theme: String
        var source: String?
        var until: Date?
        var id: String { feedID }
    }

    /// The directory (the Mac's Feeds/Directory.swift): who the people you
    /// follow vouch for, small web first, built once a week.
    struct DirectoryEntry: Codable, Identifiable, Hashable {
        var id, name, input, group: String
        var via: [String]
        var description: String
        var smallWeb: Bool
        var theme: String?
        var score: Double
        var lastPost: Date?
        var reason: String {
            var parts = [via.prefix(2).joined(separator: ", ") + (via.count > 2 ? " and \(via.count - 2) more" : "")]
            if smallWeb { parts.append("Small web") }
            if let theme { parts.append("Fits \(theme)") }
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }
}

struct FartherSuggestion: Codable, Hashable, Identifiable {
    var id: String { input.lowercased() }
    var name, input, kind, why, step: String
    var hasFeed: Bool?
    var feedTitle: String?
    var lastPost: Date?
}

struct FartherResult: Codable, Hashable {
    var theme: String
    var asked: Date
    var direction: String
    var suggestions: [FartherSuggestion]
    var prompt: String
}

extension Store {
    func farther(theme: String) -> FartherResult? { creators?.farther?[theme] }

    /// Suggestions with a feed, not followed from this phone yet.
    func fartherShown(theme: String) -> [FartherSuggestion] {
        let asked = Set(feedRequests.compactMap(\.creator))
        return (farther(theme: theme)?.suggestions ?? []).filter { $0.hasFeed == true && !asked.contains("farther:\(theme):\($0.id)") }
    }

    func follow(_ s: FartherSuggestion, theme: String) { request("follow", input: s.input, creator: "farther:\(theme):\(s.id)") }

    /// "Your Mac is asking Claude" or "Waiting for your Mac" while a request runs.
    func fartherStatus(theme: String) -> String? {
        if creators?.fartherAsking?.contains(theme) == true { return "Your Mac is asking Claude…" }
        if feedRequests.contains(where: { $0.kind == "farther" && $0.input == theme && macFeeds?.requests[$0.id] == nil }) { return "Waiting for your Mac" }
        return nil
    }

    func askFarther(theme: String) { request("farther", input: theme) }
}

/// The Mac's `PickWhy`: how a Today pick got its place.
struct PickWhy: Codable, Hashable, Sendable {
    var slot: String
    var hoursOld: Double
    var freshness: Double
    var postsPerDay: Double
    var volume: Double
    var affinity: Double
    var theme: String?
    var themeWords: Int
    var themeBonus: Double
    var mentions: Int
    var hotBonus: Double
    var creator: String?
    var creatorSaves: Int
    var creatorBonus: Double
    var score: Double
    /// Theme dials: the dial, and the theme a tried source is for.
    var dial: String? = nil
    var trial: String? = nil
    /// Social proof: your feeds whose posts link to this item.
    var linkedBy: [String]? = nil
    var linkedBonus: Double? = nil
}

extension Store {
    private static var creatorsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "creators.json")
    }

    static func loadCreators() -> CreatorsFile? {
        guard let data = try? Data(contentsOf: creatorsURL) else { return nil }
        return try? coder.1.decode(CreatorsFile.self, from: data)
    }

    func syncCreators(_ folder: URL) {
        let url = folder.appending(path: "Deck/creators.json")
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        if let data = coordinatedData(url), let file = try? Self.coder.1.decode(CreatorsFile.self, from: data) {
            creators = file
            try? data.write(to: Self.creatorsURL, options: .atomic)
        }
    }

    /// The latest request about a creator that the Mac has not handled yet.
    private func pending(_ c: CreatorsFile.Row) -> PhoneFeedRequest? {
        feedRequests.last { $0.creator == c.id && macFeeds?.requests[$0.id] == nil }
    }

    func isFollowing(_ c: CreatorsFile.Row) -> Bool {
        if let r = pending(c) { return r.kind == "follow" ? true : (r.kind == "unfollow" ? false : c.feedID != nil) }
        if let r = feedRequests.last(where: { $0.creator == c.id && $0.kind == "follow" }), macFeeds?.requests[r.id] == "followed" { return true }
        return c.feedID != nil
    }

    func isHidden(_ c: CreatorsFile.Row) -> Bool {
        if let r = pending(c), r.kind == "hide" || r.kind == "show" { return r.kind == "hide" }
        return c.hidden
    }

    /// "Waiting for your Mac" while a follow or hide is not handled yet.
    func creatorStatus(_ c: CreatorsFile.Row) -> String? {
        guard let r = pending(c) else {
            if let r = feedRequests.last(where: { $0.creator == c.id && $0.kind == "follow" }), macFeeds?.requests[r.id] == "failed" {
                return "No feed found"
            }
            return nil
        }
        return status(of: r)
    }

    func follow(_ c: CreatorsFile.Row) {
        guard c.canFollow else { return }
        request("follow", input: c.input, creator: c.id)
    }
    func unfollow(_ c: CreatorsFile.Row) {
        guard let id = c.feedID else { return }
        request("unfollow", feedID: id, creator: c.id)
    }
    func setHidden(_ c: CreatorsFile.Row, _ hidden: Bool) { request(hidden ? "hide" : "show", creator: c.id) }

    /// Next Door not followed or hidden from this phone yet.
    var nextDoor: [CreatorsFile.Near] {
        let asked = Set(feedRequests.compactMap(\.creator))
        return (creators?.nextDoor ?? []).filter { !asked.contains($0.id) }
    }

    func nextDoor(theme: String) -> [CreatorsFile.Near] {
        nextDoor.filter { ($0.themes[theme] ?? 0) > 0 }.sorted { ($0.themes[theme] ?? 0, $0.score) > ($1.themes[theme] ?? 0, $1.score) }
    }

    func follow(_ n: CreatorsFile.Near) { request("follow", input: n.input, creator: n.id) }
    func hide(_ n: CreatorsFile.Near) { request("hide", creator: n.id) }

    func creators(theme: String) -> [CreatorsFile.Row] {
        (creators?.creators ?? []).filter { !isHidden($0) && ($0.themes[theme] ?? 0) > 0 }
            .sorted { ($0.themes[theme] ?? 0, $0.score) > ($1.themes[theme] ?? 0, $1.score) }
    }
}

/// Your Graph: every creator, with filters. Tap one for its page.
struct CreatorGraphView: View {
    @Environment(Store.self) private var store
    @State private var kind = "all"
    @State private var hidden = false

    private var rows: [CreatorsFile.Row] {
        (store.creators?.creators ?? []).filter { c in
            store.isHidden(c) == hidden && (kind == "all" || (kind == "following" ? store.isFollowing(c) : c.kind == kind))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("", selection: $kind) {
                    Text("All").tag("all")
                    Text("Following").tag("following")
                    Text("Next Door").tag("nextdoor")
                    Text("Video").tag("video")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            } footer: {
                Text("The channels, writers and communities behind what you saved. Score = your saves from them, each counted by age: a save counts half after \(Int(store.creators?.halfLifeDays ?? 90)) days. Sift only proposes. A creator reaches Today only after you follow it.")
            }
            if kind == "nextdoor" {
                Section {
                    ForEach(store.nextDoor) { n in
                        NavigationLink { NeighborPage(neighbor: n) } label: { NeighborRow(neighbor: n) }
                            .swipeActions {
                                Button("Hide") { store.hide(n) }.tint(.gray)
                                Button("Follow") { store.follow(n) }.tint(.accentColor)
                            }
                    }
                } footer: {
                    Text("Creators outside your graph that 2 or more of yours link to, in the pages, video descriptions and feed items your Mac has. Each creator who links adds 1 + log(1 + its own score). Sponsor links, shops and a creator's own site do not count.")
                }
            }
            ForEach(kind == "nextdoor" ? [] : rows) { c in
                NavigationLink { CreatorPage(creator: c) } label: { CreatorRow(creator: c) }
                    .swipeActions {
                        Button(hidden ? "Show" : "Hide") { store.setHidden(c, !hidden) }.tint(.gray)
                        if c.canFollow, !store.isFollowing(c) { Button("Follow") { store.follow(c) }.tint(.accentColor) }
                    }
            }
            if store.creators == nil {
                Text("Your Mac has not shared Your Graph yet. Update Sift on the Mac to 1.7.4 or later, with iCloud Drive on.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Show hidden", isOn: $hidden)
        }
        .navigationTitle("Your Graph")
        .refreshable { store.sync() }
    }
}

struct CreatorRow: View {
    @Environment(Store.self) private var store
    let creator: CreatorsFile.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: creator.symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(creator.name).font(.body.weight(.medium)).lineLimit(1)
                    if store.isFollowing(creator) { Text("Following").font(.caption2.weight(.semibold)).foregroundStyle(.tint) }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.1f", creator.score)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        var parts = ["\(creator.count) saved"]
        if creator.recent > 0 { parts.append("\(creator.recent) in 90 days") }
        if let t = creator.topThemes.first { parts.append(t.name) }
        if let s = store.creatorStatus(creator) { parts.append(s) }
        return parts.joined(separator: " · ")
    }
}

struct CreatorPage: View {
    @Environment(Store.self) private var store
    let creator: CreatorsFile.Row
    @State private var browsing: BrowserLink?

    var body: some View {
        List {
            Section {
                if store.isFollowing(creator) {
                    Label("Following", systemImage: "checkmark").foregroundStyle(.tint)
                    if creator.feedID != nil { Button("Unfollow", role: .destructive) { store.unfollow(creator) } }
                } else if creator.canFollow {
                    Button("Follow") { store.follow(creator) }.bold()
                } else {
                    Text("No feed to follow on this platform.").foregroundStyle(.secondary)
                }
                Button(store.isHidden(creator) ? "Show in Your Graph" : "Hide") { store.setHidden(creator, !store.isHidden(creator)) }
                if let s = store.creatorStatus(creator) { Text(s).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("Your Mac finds the feed and follows it.")
            }
            if let near = creator.closeTo, !near.isEmpty {
                Section("Close to") {
                    Text(near.joined(separator: ", ")).font(.callout)
                    if let r = creator.rank {
                        Text(String(format: "Graph rank %.2f: how central this creator is to the ones you follow, by closeness in meaning.", r))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Why it is here") {
                let half = Int(store.creators?.halfLifeDays ?? 90)
                Text(String(format: "Score %.2f: %d saves. A save from today counts 1, from %d days ago 0.5, from %d days ago 0.25. %d are from the last 90 days.",
                            creator.score, creator.count, half, half * 2, creator.recent))
                Text(String(format: store.isFollowing(creator) ? "In Today its new posts get + %.2f on their score." : "If you follow it, its new posts get + %.2f on their score in Today.", creator.bonus))
            }
            .font(.callout)
            if !creator.themes.isEmpty {
                Section("In your themes") {
                    ForEach(creator.topThemes, id: \.name) { t in
                        LabeledContent(t.name, value: "\(t.count)")
                    }
                }
            }
            Section("What you saved") {
                ForEach(creator.saves, id: \.url) { s in
                    Button {
                        if let u = URL(string: s.url) { browsing = BrowserLink(url: u) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? s.url : s.title).lineLimit(2).foregroundStyle(.primary)
                            Text([s.date.formatted(date: .abbreviated, time: .omitted), s.theme].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if creator.count > creator.saves.count {
                    Text("and \(creator.count - creator.saves.count) more on your Mac").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(creator.name)
        .sheet(item: $browsing) { InAppBrowser(url: $0.url).ignoresSafeArea() }
    }
}

/// How Today Works on the phone: the formula, the signals and today's picks
/// with their scores. The numbers match the Mac's `TodayBuilder`.
struct AlgorithmView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            Section {
                Text("score = fresh × volume × reading + graph + theme + linked + hot").font(.system(.callout, design: .monospaced))
                row("fresh", "exp(-hours / 36)", "1 when new, about 0.5 after a day")
                row("volume", "1 / √(posts a day)", "a rare post counts more")
                row("reading", "1 + 0.8 × affinity", "affinity is -1…1, from what you did with the feed")
                row("graph", "0.12 × log2(1 + saves)", "a creator you follow in Your Graph, max 0.6")
                row("theme", "0.15 × shared words", "3 or more words shared with a theme, max 0.6")
                row("linked", "0.3 × feeds, max 0.9", "your other feeds link to it in their posts this week")
                row("hot", "0.6 × (feeds − 1)", "the same link in 2 or more of your feeds")
            } header: { Text("The Today score") } footer: {
                Text("Don't Miss items come first, then Hot, then by score. Each of Scan, Watch and Read gets at least 5 picks; unseen items up to 14 days old fill a mode that has fewer. One \"New to you\" and one random \"Something different\" per mode. A link 2 or more of your feeds point to, but none carries, gets its own place (\"Linked by\"), at most 3. More Like This on any item opens a trail: same creator, same theme or shared words, 20 at most. Today, trails and Your Graph use no AI.")
            }
            Section {
                row("Keep", "+3", "")
                row("Open, play, mark unseen", "+1", "")
                row("Time on screen", "up to +1", "0.05 a second")
                row("Quick skip", "-0.4", "under 1.5 seconds")
            } header: { Text("What Sift learns from you") } footer: {
                Text("A signal counts less as it ages: about a third after 30 days. This phone's signals go to your Mac through iCloud Drive and nowhere else.")
            }
            Section("Today's picks, by score") {
                let picks = (store.today?.picks ?? []).sorted { ($0.why?.score ?? -1) > ($1.why?.score ?? -1) }
                if picks.isEmpty { Text("No picks yet.").foregroundStyle(.secondary) }
                ForEach(picks.prefix(60)) { p in
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.why.map { String(format: "%.2f", $0.score) } ?? "–").font(.caption.monospacedDigit()).frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(.subheadline).lineLimit(1)
                            Text([place(p.why?.slot), p.reason].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("How Today Works")
    }

    private func row(_ name: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name).bold(); Spacer(); Text(value).font(.system(.caption, design: .monospaced)) }
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func place(_ slot: String?) -> String {
        switch slot {
        case "dontMiss": "Don't Miss"
        case "fill": "Fill"
        case "explore": "New to you"
        case "wildcard": "Random"
        case "linked": "Linked by"
        case "trial": "Trying"
        case "ranked": "Ranked"
        default: ""
        }
    }
}

struct NeighborRow: View {
    let neighbor: CreatorsFile.Near

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.2.wave.2").foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(neighbor.name).font(.body.weight(.medium)).lineLimit(1)
                Text(neighbor.linkedText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(String(format: "%.1f", neighbor.score)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct NeighborPage: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let neighbor: CreatorsFile.Near
    @State private var browsing: BrowserLink?

    var body: some View {
        List {
            Section {
                Button("Follow") { store.follow(neighbor); dismiss() }.bold()
                Button("Hide") { store.hide(neighbor); dismiss() }
                Button("Open Site") { open(neighbor.input.hasPrefix("http") ? neighbor.input : "https://" + neighbor.input) }
            } footer: { Text("Your Mac finds the feed and follows it.") }
            Section("Why it is here") {
                Text(String(format: "Score %.2f: %d creators in your graph link to it, %d times in all.", neighbor.score, neighbor.linkedBy.count, neighbor.mentions))
                Text("Linked by " + neighbor.linkedBy.joined(separator: ", "))
            }
            .font(.callout)
            Section("The links") {
                ForEach(neighbor.evidence, id: \.self) { e in
                    Button { open(e.itemURL) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(e.from): \(e.item.isEmpty ? e.itemURL : e.item)").lineLimit(2).foregroundStyle(.primary)
                            Text(e.link).font(.caption).foregroundStyle(.tint).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .navigationTitle(neighbor.name)
        .sheet(item: $browsing) { InAppBrowser(url: $0.url).ignoresSafeArea() }
    }

    private func open(_ s: String) { if let u = URL(string: s) { browsing = BrowserLink(url: u) } }
}
