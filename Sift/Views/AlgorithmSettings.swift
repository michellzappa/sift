import SwiftUI

/// Settings > Algorithm (owner, 2026-11-17: "settings or somewhere should
/// have algo visibility"). Every rule and number Sift ranks by, live: the
/// Today score, today's picks with their scores, what Sift learned per
/// feed, Your Graph, and where Claude is used. The numbers come from the
/// same constants the code uses (`TodayBuilder`, `Creators`, `FeedSignals`),
/// so this pane cannot drift from the ranking.
struct AlgorithmSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Everything Sift ranks by, with the live numbers. It all runs on this Mac. Today and Your Graph use no AI: they are the plain formulas below.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                section("The Today score") { formula }
                section("Today's picks, by score") { picks }
                section("The rules") { TodayRules() }
                section("What Sift learns from you") { signals }
                section("Your feeds") { FeedStandingsList() }
                section("Your Graph") { graph }
                section("Where AI is used") { ai }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    private func line(_ name: String, _ value: String, _ note: String) -> some View {
        GridRow {
            Text(name).fontWeight(.medium)
            Text(value).font(.system(.callout, design: .monospaced))
            Text(note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formula: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("score = fresh × volume × reading + graph + theme + linked + hot")
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                line("fresh", "exp(-hours / 36)", "1 when new, about 0.5 after a day")
                line("volume", "1 / √(posts a day)", "a feed's rare post counts more than the 30th post of a busy one")
                line("reading", "1 + 0.8 × affinity", "affinity is -1…1, from what you did with the feed")
                line("graph", "0.12 × log2(1 + saves), max 0.6", "only for a creator you follow in Your Graph")
                line("theme", "0.15 × shared words, max 0.6", "needs 3 or more words in common with a theme")
                line("linked", "0.3 × feeds, max 0.9", "your other feeds link to it in their posts this week")
                line("hot", "0.6 × (feeds − 1)", "the same link in 2 or more of your feeds")
            }
            .font(.callout)
            Text("Places: Don't Miss items first, then Hot, then by score. A Normal feed gets up to \(TodayBuilder.perFeed) unseen picks at a time, a Best Only feed 1. Each mode (Scan, Watch, Read) gets at least \(TodayBuilder.perMode); if it has fewer, unseen items up to \(Int(TodayBuilder.fillWindowDays)) days old fill it. Then one \"New to you\" and one random \"Something different\" per mode. A link that \(TodayBuilder.linkedMinFeeds) or more of your feeds point to, but none carries, gets its own place (\"Linked by\"), at most \(TodayBuilder.linkedMaxPicks).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var picks: some View {
        let rows = model.todayPicks.sorted { ($0.why?.score ?? -1) > ($1.why?.score ?? -1) }
        return VStack(alignment: .leading, spacing: 4) {
            if rows.isEmpty {
                Text("Today has no picks yet.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Score"); Text("Place"); Text("Item")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(rows.prefix(60), id: \.url) { p in
                        GridRow {
                            Text(p.why.map { String(format: "%.2f", $0.score) } ?? "–").monospacedDigit()
                            Text(place(p.why?.slot)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.title).lineLimit(1)
                                Text([p.feedTitle, p.reason].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .font(.callout)
                    }
                }
                Text("Open a pick in Today and look under \"Why this is here\" for each factor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func place(_ slot: String?) -> String {
        switch slot {
        case "dontMiss": "Don't Miss"
        case "fill": "Fill"
        case "explore": "New to you"
        case "wildcard": "Random"
        case "linked": "Linked by"
        case "ranked": "Ranked"
        default: "Older pick"
        }
    }

    private var signals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Each thing you do with a Today pick adds to its feed's affinity. A signal counts less as it ages (it falls to about a third after 30 days). The sum goes through tanh, so affinity stays between -1 and 1. Signals from your iPhone count the same.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                line("Keep", "+3", "")
                line("Open, play, mark unseen", "+1", "")
                line("Reading time", "up to +1", "0.05 for each second on screen")
                line("Quick skip", "-0.4", "less than 1.5 seconds on screen (phone)")
            }
            .font(.callout)
        }
    }

    private var graph: some View {
        let followed = model.visibleCreators.filter { $0.feedID != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("The channels, writers and communities behind your saves. Score = the sum of your saves from a creator, each counted 0.5^(age / \(Int(Creators.halfLifeDays)) days). A creator needs \(Creators.minSaves) saves to show. Sift only proposes: a creator reaches Today after you follow it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("\(model.visibleCreators.count) creators · \(followed) followed · \(model.state.hiddenCreators.count) hidden")
                .font(.callout)
            Text("Next Door: creators outside your graph that \(NextDoor.minLinkers) or more of yours link to, in the pages, video descriptions and feed items Sift already has. Each creator who links adds 1 + log(1 + its own score). Sponsor links, shops, tip jars and a creator's own site do not count. \(model.visibleNeighbors.count) found.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Farther: on request, per theme, your own Claude reads the theme's newest saved titles and history and names sources one step beyond: deeper, adjacent and one counterpoint. Sift checks each for a feed; only those with one can be followed. Each answer keeps the exact text Claude saw.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Trails: More Like This (T) on any item opens up to \(Trail.size) unseen items near it, from your saves and the last \(Int(Trail.offeredDays)) days of your feeds. Same creator counts 3, same theme 1.5, each shared word 0.6. At most \(Trail.perCreator) per creator. No AI.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open Your Graph") { model.navigationRequest = .creators }
        }
    }

    private var ai: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude (your own login or key): finding themes, sorting links that the on-device model is not sure of, connections between themes, and Farther suggestions when you ask. It gets titles, addresses and previews, never full pages.")
            Text("Apple's on-device model: the first sorting pass and summaries, on this Mac.")
            Text("No AI: Today, Your Graph, Next Door, trails, Scan / Watch / Read, duplicates, search.")
        }
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
