import SwiftUI

// People on the phone: one person, every place they publish. The Mac finds
// them (Sift/Feeds/People.swift) and shares them in Deck/creators.json; the
// phone asks the Mac to follow a place through follows/ (creator
// "place:<id>"), like every other follow.

extension Store {
    var people: [CreatorsFile.PersonRow] { creators?.people ?? [] }

    func follow(_ place: CreatorsFile.PlaceRow) { request("follow", input: place.input, creator: "place:" + place.id) }

    /// "Waiting for your Mac", "Following", "No feed found", or nil.
    func placeStatus(_ place: CreatorsFile.PlaceRow) -> String? {
        if place.followed { return "Following" }
        guard let r = feedRequests.last(where: { $0.creator == "place:" + place.id }) else { return nil }
        return status(of: r) ?? "Following"
    }
}

struct PeopleListView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.people) { person in
                    NavigationLink { PersonPage(person: person) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).font(.body.weight(.medium))
                            Text(person.places.map(\.platformName).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text(store.people.isEmpty
                     ? "Your Mac finds people from the sites and Bluesky accounts you follow and the writers in Your Graph. They show here after it has checked them."
                     : "Sift groups places only from what each person publishes: rel=me links, the profiles their own site links to, and a Bluesky handle that is their domain.")
            }
        }
        .navigationTitle("People")
    }
}

struct PersonPage: View {
    @Environment(Store.self) private var store
    let person: CreatorsFile.PersonRow
    @State private var browsing: BrowserLink?

    var body: some View {
        List {
            Section("Places") {
                ForEach(person.places) { place in
                    HStack(spacing: 10) {
                        Image(systemName: place.symbol).foregroundStyle(.secondary).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.platformName).font(.body.weight(.medium))
                            Text(place.handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let s = store.placeStatus(place) {
                            Text(s).font(.caption).foregroundStyle(.secondary)
                        } else if place.hasFeed {
                            Button("Follow") { store.follow(place) }.buttonStyle(.bordered)
                        } else {
                            Text("No feed").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if let u = URL(string: place.url) { browsing = BrowserLink(url: u) } }
                }
            }
            let missing = person.places.filter { $0.hasFeed && store.placeStatus($0) == nil }
            if !missing.isEmpty {
                Section {
                    Button("Follow Everywhere") { missing.forEach(store.follow) }
                } footer: {
                    Text("Your Mac follows \(missing.map(\.platformName).joined(separator: ", ")). One post on several platforms shows once in Today.")
                }
            }
            Section("How Sift knows") {
                ForEach(person.evidence, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(person.name)
        .sheet(item: $browsing) { InAppBrowser(url: $0.url).ignoresSafeArea() }
    }
}

// MARK: Directory

extension Store {
    var directoryEntries: [CreatorsFile.DirectoryEntry] {
        let dismissed = Set(feedRequests.filter { $0.kind == "dismiss" }.compactMap(\.creator))
        return (creators?.directory ?? []).filter { !dismissed.contains("directory:" + $0.id) }
    }
    func follow(_ e: CreatorsFile.DirectoryEntry) { request("follow", input: e.input, creator: "directory:" + e.id) }
    func dismiss(_ e: CreatorsFile.DirectoryEntry) { request("dismiss", creator: "directory:" + e.id) }
    func directoryStatus(_ e: CreatorsFile.DirectoryEntry) -> String? {
        guard let r = feedRequests.last(where: { $0.kind == "follow" && $0.creator == "directory:" + e.id }) else { return nil }
        return status(of: r) ?? "Following"
    }
}

/// Who the people you follow vouch for, from your Mac. It ends.
struct DirectoryView: View {
    @Environment(Store.self) private var store
    private let groups = [("blog", "Blogs"), ("newsletter", "Newsletters"), ("bluesky", "Bluesky"), ("mastodon", "Mastodon"), ("podcast", "Podcasts")]

    var body: some View {
        let all = store.directoryEntries
        List {
            ForEach(groups, id: \.0) { g in
                let rows = all.filter { $0.group == g.0 }
                if !rows.isEmpty {
                    Section(g.1) {
                        ForEach(rows) { e in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(e.name).font(.body.weight(.medium)).lineLimit(1)
                                    if e.smallWeb {
                                        Text("Small web").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.green.opacity(0.15))).foregroundStyle(.green)
                                    }
                                    Spacer()
                                    if let s = store.directoryStatus(e) {
                                        Text(s).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Button("Follow") { store.follow(e) }.buttonStyle(.bordered).controlSize(.small)
                                    }
                                }
                                Text(e.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if !e.description.isEmpty { Text(e.description).font(.caption).foregroundStyle(.tertiary).lineLimit(2) }
                            }
                            .swipeActions { Button("Not Interested") { store.dismiss(e) }.tint(.gray) }
                        }
                    }
                }
            }
            Section {
            } footer: {
                Text(all.isEmpty
                     ? "Your Mac asks the blogs, newsletters and accounts you follow whom they recommend, once a week. Only their public addresses leave your Mac."
                     : "That's all for this week. Each name shows who vouches for it.")
            }
        }
        .navigationTitle("Directory")
    }
}

// MARK: Theme dials

/// Stay, Lean In or Explore for one theme (the Mac's ThemeDial).
enum PhoneDial: String, CaseIterable, Identifiable {
    case stay, leanIn, explore
    var id: String { rawValue }
    var title: String { self == .stay ? "Stay" : self == .leanIn ? "Lean In" : "Explore" }
    var help: String {
        switch self {
        case .stay: "Only the feeds you follow."
        case .leanIn: "Twice the theme's lift in Today, and your Mac tries up to 2 creators you already save from here."
        case .explore: "Your Mac tries up to 3 sources one step out: Next Door, the directory and Farther."
        }
    }
}

extension Store {
    /// The dial the Mac has, or the one this phone asked for last.
    func dial(_ theme: String) -> PhoneDial {
        if let r = feedRequests.last(where: { $0.kind == "dial" && $0.input == theme }), macFeeds?.requests[r.id] == nil {
            return PhoneDial(rawValue: r.priority ?? "") ?? .stay
        }
        return PhoneDial(rawValue: creators?.dials?[theme] ?? "") ?? .stay
    }
    func setDial(_ d: PhoneDial, theme: String) { request("dial", input: theme, priority: d.rawValue) }
    func trials(_ theme: String) -> [CreatorsFile.TrialRow] {
        let done = Set(feedRequests.filter { $0.kind.hasPrefix("trial-") }.compactMap(\.feedID))
        return (creators?.trials ?? []).filter { $0.theme == theme && !done.contains($0.feedID) }
    }
}

/// The dial and the tried sources, for the top of a theme page.
struct ThemeDialSection: View {
    @Environment(Store.self) private var store
    let theme: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("In Today", selection: Binding(get: { store.dial(theme) }, set: { store.setDial($0, theme: theme) })) {
                ForEach(PhoneDial.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(store.dial(theme).help).font(.caption).foregroundStyle(.secondary)
            ForEach(store.trials(theme)) { t in
                HStack(spacing: 8) {
                    Image(systemName: "flask").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trying \(t.title)").font(.subheadline).lineLimit(1)
                        Text([t.source, t.until.map { "until \($0.formatted(date: .abbreviated, time: .omitted))" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Follow") { store.request("trial-follow", feedID: t.feedID) }.buttonStyle(.bordered).controlSize(.small)
                    Button("Stop") { store.request("trial-stop", feedID: t.feedID) }.controlSize(.small)
                }
            }
        }
    }
}

// MARK: Not interested

extension Store {
    /// Not interested in a Today pick: the Mac applies it (source, topic or
    /// story); the pick counts as seen here at once.
    func notInterested(_ pick: TodayPick, _ reason: String) {
        request("less", input: pick.url, feedID: pick.feedID, priority: reason)
        setSeen([pick.item], true, mode: "today")
    }
}

// MARK: Triage (Scan's Saved part)

extension Store {
    /// Keep, let go or send a saved post. It counts as seen here at once;
    /// the Mac carries it out (request "triage": input URL, priority decision).
    func triage(_ item: Item, _ decision: Decision) {
        let kind: String
        switch decision {
        case .letGo: kind = "letGo"
        case .send: kind = "send"
        default: kind = "keep"
        }
        request("triage", input: item.url, priority: kind)
        record(item, decision, mode: "triage", position: 0)
        setSeen([item], true, mode: "triage")
    }
}
