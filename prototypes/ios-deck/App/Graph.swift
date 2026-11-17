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
    var schema: Int
    var halfLifeDays: Double
    var minSaves: Int
    var creators: [Row]
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

    func follow(_ c: CreatorsFile.Row) { request("follow", input: c.input, creator: c.id) }
    func unfollow(_ c: CreatorsFile.Row) {
        guard let id = c.feedID else { return }
        request("unfollow", feedID: id, creator: c.id)
    }
    func setHidden(_ c: CreatorsFile.Row, _ hidden: Bool) { request(hidden ? "hide" : "show", creator: c.id) }

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
                    Text("Video").tag("video")
                    Text("Writing").tag("writing")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            } footer: {
                Text("The channels, writers and communities behind what you saved. Score = your saves from them, each counted by age: a save counts half after \(Int(store.creators?.halfLifeDays ?? 90)) days. Sift only proposes. A creator reaches Today only after you follow it.")
            }
            ForEach(rows) { c in
                NavigationLink { CreatorPage(creator: c) } label: { CreatorRow(creator: c) }
                    .swipeActions {
                        Button(hidden ? "Show" : "Hide") { store.setHidden(c, !hidden) }.tint(.gray)
                        if !store.isFollowing(c) { Button("Follow") { store.follow(c) }.tint(.accentColor) }
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
                } else {
                    Button("Follow") { store.follow(creator) }.bold()
                }
                Button(store.isHidden(creator) ? "Show in Your Graph" : "Hide") { store.setHidden(creator, !store.isHidden(creator)) }
                if let s = store.creatorStatus(creator) { Text(s).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("Your Mac finds the feed and follows it.")
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
                Text("score = fresh × volume × reading + graph + theme + hot").font(.system(.callout, design: .monospaced))
                row("fresh", "exp(-hours / 36)", "1 when new, about 0.5 after a day")
                row("volume", "1 / √(posts a day)", "a rare post counts more")
                row("reading", "1 + 0.8 × affinity", "affinity is -1…1, from what you did with the feed")
                row("graph", "0.12 × log2(1 + saves)", "a creator you follow in Your Graph, max 0.6")
                row("theme", "0.15 × shared words", "3 or more words shared with a theme, max 0.6")
                row("hot", "0.6 × (feeds − 1)", "the same link in 2 or more of your feeds")
            } header: { Text("The Today score") } footer: {
                Text("Don't Miss items come first, then Hot, then by score. Each of Scan, Watch and Read gets at least 5 picks; unseen items up to 14 days old fill a mode that has fewer. One \"New to you\" and one random \"Something different\" per mode. Today and Your Graph use no AI.")
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
        case "ranked": "Ranked"
        default: ""
        }
    }
}
