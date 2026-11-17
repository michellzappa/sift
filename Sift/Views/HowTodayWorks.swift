import SwiftUI

/// What Today knows about one feed (AppModel.standings).
struct FeedStanding: Identifiable {
    let feed: Feed
    let priority: FeedPriority
    let auto: Bool
    let postsPerDay: Double
    /// -1…1 from your keeps, opens, reading time and skips (FeedSignals).
    let affinity: Double
    let signals: Int
    let keeps: Int
    var id: String { feed.id }

    /// "About 12 posts a day".
    var rate: String {
        let d = postsPerDay
        if d == 0 { return "No posts in the last 2 weeks" }
        if d >= 1.5 { return "About \(Int(d.rounded())) posts a day" }
        if d * 7 >= 1.5 { return "About \(Int((d * 7).rounded())) posts a week" }
        return "A few posts a month"
    }

    /// "Best Only (Auto)" or "Don't Miss".
    var place: String { auto ? "\(priority.label) (Auto)" : priority.label }

    /// Why Auto chose what it chose, or nil for a choice you made.
    var autoReason: String? {
        guard auto else { return nil }
        return priority == .best
            ? "Busy feed: over \(Int(FeedPriority.busyPerDay)) posts a day, so only its strongest items reach Today."
            : "Up to \(TodayBuilder.perFeed) new items at a time."
    }

    /// What Sift learned from your reading.
    var learned: String {
        if signals < 3 { return "Still learning: you have read little from it" }
        if affinity > 0.4 { return "You read it often: its items rank higher" }
        if affinity > 0.1 { return "You read it sometimes: a small lift" }
        if affinity < -0.1 { return "You mostly skip it: its items rank lower" }
        return "No lean either way"
    }
}

/// The Today ranking in plain words, with the live numbers per feed. Opened
/// from Today's toolbar (?) and Help > How Today Works. The text must match
/// `TodayBuilder.build`; change both together.
struct HowTodayWorks: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("How Today Works").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TodayRules()
                    Divider()
                    FeedStandingsList()
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 640)
    }
}

/// The Today rules in plain words. Shared by the sheet and Settings >
/// Algorithm.
struct TodayRules: View {
    var body: some View { rules }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today picks from your feeds on this Mac. Nothing goes to a server and no Claude call is made. Every pick says why it is there.")
                .foregroundStyle(.secondary)
            rule("1", "What can come in", "Items from the last \(Int(TodayBuilder.windowDays)) days that you have not seen or kept. Don't Miss feeds: \(Int(TodayBuilder.mustWindowDays)) days.")
            rule("2", "Don't Miss first", "Every new item from a feed set to Don't Miss, newest first.")
            rule("3", "Hot", "A link that is in two or more of your feeds right now (a Hacker News post about an article another feed has, for example). The more feeds, the higher.")
            rule("4", "Then by score", "Newer is higher: an item loses about half its weight in a day. A rare post counts more than the 30th post of a busy feed. Feeds you read often get up to 80% more. Items that share words with one of your themes get a lift. A creator from Your Graph gets a lift by how many of their links you saved (14 saves: about +0.47).")
            rule("5", "Fair shares", "A Normal feed has at most \(TodayBuilder.perFeed) unseen items in Today at a time; its next one comes in as you read. A Best Only feed gets 1, and only when the item is Hot, fits a theme or comes from a feed you read often. Not in Today: none.")
            rule("6", "Every mode gets its share", "Scan, Watch and Read each get at least \(TodayBuilder.perMode) picks when there are enough. If a mode has fewer, Sift adds unseen items of that mode from the last \(Int(TodayBuilder.fillWindowDays)) days. So on a quiet day for your video feeds, Watch still has something.")
            rule("7", "Two extra slots per mode", "\"New to you\": one item from a feed Sift knows little about yet, so new feeds get a chance. \"Something different\": one item from a feed not in Today yet.")
            rule("8", "It updates", "New picks go on top after each feed check. Items you have seen stay in their place until they are \(Int(TodayBuilder.windowDays)) days old (older picks that filled a mode: \(Int(TodayBuilder.fillWindowDays)) days). Rebuild Today starts again from nothing.")
            rule("9", "What it learns", "Keeping, opening, reading time and playing raise a feed; a quick skip lowers it a little. It counts the last month most, on this Mac and your iPhone.")
            rule("10", "Your Graph", "The channels, writers and communities behind what you saved, ranked by your saves (a save counts half after \(Int(Creators.halfLifeDays)) days). Sift only proposes them. A creator reaches Today only after you follow it.")
            rule("11", "Check any pick", "Open a pick and look under \"Why this is here\": every number of its score, and which rule gave it its place.")
        }
    }

    private func rule(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 22, height: 22).background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

/// Every followed feed with its place in Today and what Sift learned.
struct FeedStandingsList: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [FeedStanding] = []

    var body: some View {
        feedTable
            .onAppear { rows = model.standings().sorted { $0.feed.title.localizedCaseInsensitiveCompare($1.feed.title) == .orderedAscending } }
    }

    private var feedTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your feeds").font(.headline)
            Text("Change how a feed takes part with the menu, or right-click it in the sidebar.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(rows) { r in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.feed.title).lineLimit(1)
                        Text("\(r.rate) · \(r.learned)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PriorityMenu(standing: r) { rows = model.standings().sorted { $0.feed.title.localizedCaseInsensitiveCompare($1.feed.title) == .orderedAscending } }
                }
                .padding(.vertical, 4)
            }
            if rows.isEmpty { Text("You follow no feeds yet.").foregroundStyle(.secondary) }
        }
    }
}

/// Auto (with what Auto chose), Don't Miss, Normal, Best Only, Not in Today.
struct PriorityMenu: View {
    @Environment(AppModel.self) private var model
    let standing: FeedStanding
    var changed: () -> Void = {}

    var body: some View {
        Menu(standing.place) {
            Button("Auto") { model.setPriority(standing.feed, nil); changed() }
            Divider()
            ForEach(FeedPriority.allCases, id: \.self) { p in
                Button(p.label) { model.setPriority(standing.feed, p); changed() }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(standing.autoReason ?? "You chose this.")
    }
}

/// One line above a single feed's list: its place in Today and what Sift
/// learned, with the menu to change it.
struct FeedStandingBar: View {
    @Environment(AppModel.self) private var model
    let feed: Feed

    var body: some View {
        if let s = model.standings([feed]).first {
            HStack(spacing: 8) {
                Text("In Today:").foregroundStyle(.secondary)
                PriorityMenu(standing: s)
                Text("· \(s.rate) · \(s.learned)").foregroundStyle(.secondary).lineLimit(1)
                Button { model.showHowToday = true } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.borderless).help("How Today Works")
            }
            .font(.callout)
        }
    }
}
