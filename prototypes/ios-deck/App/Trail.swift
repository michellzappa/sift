import SwiftUI

// Trails on the phone: "More like this" from any item. The same rules as
// the Mac's Sift/Engine/Trail.swift (change both together): same creator 3,
// same theme 1.5, each shared word 0.6 (up to 5), a score of 1.8 to join,
// unseen only, at most 4 per creator, 20 in all. The phone uses what it has:
// your saved items in the deck and Today's picks. Local, no AI.

enum PhoneTrail {
    static let size = 20
    static let perCreator = 4
    static let minScore = 1.8

    struct Node {
        var item: Item
        var creator: String
        var theme: String?
    }

    /// Lowercased words of five letters or more, without common ones
    /// (the Mac's `TodayBuilder.words`).
    static func words(_ s: String) -> Set<String> {
        let stop: Set<String> = ["about", "after", "their", "there", "these", "those", "which", "would", "could", "should", "where", "while", "other", "every", "still", "first", "years", "people", "things"]
        return Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 && !stop.contains($0) })
    }

    static func build(seed: Node, pool: [Node], isSeen: (String) -> Bool) -> [(Item, String)] {
        let seedWords = words(seed.item.title + " " + seed.item.summary)
        var seenURL: Set<String> = [seed.item.url]
        var scored: [(Node, Double, String)] = []
        for n in pool {
            guard !isSeen(n.item.url), seenURL.insert(n.item.url).inserted else { continue }
            let same = !n.creator.isEmpty && n.creator == seed.creator
            let theme = n.theme != nil && n.theme == seed.theme
            let shared = words(n.item.title + " " + n.item.summary).intersection(seedWords).count
            var score = Double(min(shared, 5)) * 0.6
            if same { score += 3 }
            if theme { score += 1.5 }
            guard score >= minScore else { continue }
            var parts: [String] = []
            if same { parts.append("Same creator") }
            if theme, let t = n.theme { parts.append("Same theme: \(t)") }
            if shared > 0 { parts.append("\(shared) word\(shared == 1 ? "" : "s") in common") }
            scored.append((n, score, parts.joined(separator: " · ")))
        }
        scored.sort { $0.1 > $1.1 }
        var per: [String: Int] = [:]
        var out: [(Item, String)] = []
        for (n, _, why) in scored where out.count < size {
            guard per[n.creator, default: 0] < perCreator else { continue }
            per[n.creator, default: 0] += 1
            out.append((n.item, why))
        }
        return out
    }
}

extension Store {
    /// A deck item as a trail node: its channel or writer, else its site.
    func trailNode(_ item: Item) -> PhoneTrail.Node {
        if let pick = today?.picks.first(where: { $0.url == item.url }) { return trailNode(pick) }
        let creator = (item.author?.isEmpty == false ? item.author! : item.site).lowercased()
        return PhoneTrail.Node(item: item, creator: creator, theme: deck.themes.contains { $0.name == item.theme } ? item.theme : nil)
    }

    /// A Today pick as a trail node: its feed is the creator; "Fits X" is
    /// its theme.
    func trailNode(_ pick: TodayPick) -> PhoneTrail.Node {
        let theme = pick.why?.theme ?? (pick.reason.hasPrefix("Fits ") ? String(pick.reason.dropFirst(5)) : nil)
        var item = pick.item
        if let theme { item.theme = theme }
        return PhoneTrail.Node(item: item, creator: pick.feedTitle.lowercased(), theme: theme)
    }

    func trail(from item: Item) -> [(Item, String)] {
        let pool = deck.items.map(trailNode) + (today?.picks ?? []).map(trailNode)
        return PhoneTrail.build(seed: trailNode(item), pool: pool, isSeen: isSeen)
    }
}

/// The trail as a list that ends. A tap reads; More Like This on a row
/// starts a new trail from there.
struct TrailSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var seed: Item
    @State private var reading: Item?
    @State private var steps: [(Item, String)] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("More like").font(.caption).foregroundStyle(.secondary)
                        Text(seed.title).font(.headline).lineLimit(3)
                        Text("Same creator, same theme or words in common, from your saves and Today. Unseen only. It ends after \(PhoneTrail.size).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(steps, id: \.0.url) { item, why in
                        Button { reading = item } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                LibraryRow(item: item, mode: item.readingMode == .scan ? .scan : .read)
                                if !why.isEmpty { Text(why).font(.caption2).foregroundStyle(.tertiary) }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { restart(item) } label: { Label("More Like This", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                        }
                    }
                } footer: {
                    Text(steps.isEmpty ? "Nothing near this yet. Save or follow more around it." : "End of the trail.")
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
            .navigationTitle("Trail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .onAppear { if steps.isEmpty { steps = store.trail(from: seed) } }
        }
    }

    private func restart(_ item: Item) {
        seed = item
        steps = store.trail(from: item)
    }
}
