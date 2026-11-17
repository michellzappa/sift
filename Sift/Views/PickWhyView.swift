import SwiftUI

/// "Why this is here": the rule that gave a Today pick its place and every
/// number of its score (`PickWhy`, made by `TodayBuilder.build`). Closed by
/// default; the choice is kept.
struct PickWhyView: View {
    @Environment(AppModel.self) private var model
    let why: PickWhy
    let feedTitle: String
    @AppStorage("why.open") private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 6) {
                Text(slotText).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if why.slot != "dontMiss" {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        row("Fresh", String(format: "× %.2f", why.freshness), "\(age) old; halves in about a day")
                        row("Volume", String(format: "× %.2f", why.volume), String(format: "%@ posts %.1f a day; rarer posts count more", feedTitle, why.postsPerDay))
                        row("Your reading", String(format: "× %.2f", 1 + 0.8 * why.affinity), affinityText)
                        if why.creatorSaves > 0, let c = why.creator {
                            row("Your Graph", String(format: "+ %.2f", why.creatorBonus), "you saved \(why.creatorSaves) from \(c)")
                        }
                        if let t = why.theme {
                            if why.dial == ThemeDial.leanIn.rawValue, why.slot != "trial" {
                                row("Lean In", "× 2", "\(t) is set to Lean In, so its lift counts twice")
                            }
                            if let sim = why.themeSimilarity {
                                row("Theme", String(format: "+ %.2f", why.themeBonus), String(format: "close in meaning to %@ (%.2f), on this Mac", t, sim))
                            } else {
                                row("Theme", String(format: "+ %.2f", why.themeBonus), "\(why.themeWords) words shared with \(t)")
                            }
                        }
                        if let t = why.mutedTheme {
                            row("Not interested", String(format: "− %.2f", why.mutedPenalty ?? 0), "you asked for less about \(t)")
                        }
                        if let by = why.vouchedBy, !by.isEmpty {
                            row("Vouched", String(format: "+ %.2f", why.vouchBonus ?? 0), by.joined(separator: ", ") + " (directory, first \(Int(TodayBuilder.vouchDays)) days)")
                        }
                        if let names = why.linkedBy, !names.isEmpty {
                            row("Linked", String(format: "+ %.2f", why.linkedBonus ?? 0), "posts in \(names.joined(separator: ", ")) link here")
                        }
                        if why.mentions > 1 {
                            row("Hot", String(format: "+ %.2f", why.hotBonus), "in \(why.mentions) of your feeds")
                        }
                        Divider().gridCellColumns(3)
                        row("Score", String(format: "%.2f", why.score), "higher comes first")
                    }
                    .font(.callout)
                }
                Button("How Today Works") { model.showHowToday = true }
                    .buttonStyle(.link).font(.callout)
            }
            .padding(.top, 4)
        } label: {
            Text("Why this is here").font(.callout.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func row(_ name: String, _ value: String, _ note: String) -> some View {
        GridRow {
            Text(name)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
            Text(note).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var age: String {
        why.hoursOld < 48 ? "\(Int(why.hoursOld.rounded())) hours" : "\(Int((why.hoursOld / 24).rounded())) days"
    }

    private var affinityText: String {
        switch why.affinity {
        case let a where a > 0.4: "you often keep, open or play this feed"
        case let a where a > 0.05: "you sometimes open this feed"
        case let a where a < -0.05: "you often skip this feed"
        default: "Sift knows little about this feed yet"
        }
    }

    private var slotText: String {
        switch why.slot {
        case "dontMiss": "Your feed \(feedTitle) is set to Don't Miss: every new item comes in first, newest first."
        case "fill": "This mode had fewer than \(TodayBuilder.perMode) picks, so Sift added an unseen item from the last \(Int(TodayBuilder.fillWindowDays)) days, best score first."
        case "explore": "New to you: Sift knows little about this feed yet, so it gets one slot to show what it brings."
        case "trial": "Trying for \(why.trial ?? "a theme"): that theme is set to \(ThemeDial(why.dial).title), so Sift tries a few sources for it. Up to \(ThemeDial(why.dial).picks) of their items at a time. Follow the source to keep it; it goes after \(Int(Trials.days)) days otherwise."
        case "linked": "Linked by your feeds: \(why.linkedBy?.count ?? 0) of the feeds you follow link to this in their posts this week, but none carries it as an item. At most \(TodayBuilder.linkedMaxPicks) such picks at a time."
        case "wildcard": "Something different: one item from a feed not in Today yet, picked at random, not by score."
        default: "Ranked by score among unseen items from the last \(Int(TodayBuilder.windowDays)) days."
        }
    }
}
