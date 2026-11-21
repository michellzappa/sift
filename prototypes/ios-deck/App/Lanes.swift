import SwiftUI

// Custom lanes on the phone: the Mac keeps the rules and their items
// (Sift/Engine/Lanes.swift) and writes iCloud Drive/Sift/Deck/lanes.json.

struct LanesFile: Codable, Sendable {
    struct Lane: Codable, Hashable, Sendable { var id, name: String }
    struct Row: Codable, Identifiable, Hashable, Sendable {
        var lane: Lane
        var rule: String
        var picks: [TodayPick]
        var id: String { lane.id }
    }
    var schema: Int
    var built: Date
    var lanes: [Row]
}

extension Store {
    static var lanesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "lanes.json")
    }

    static func loadLanes() -> LanesFile? {
        guard let data = try? Data(contentsOf: lanesURL) else { return nil }
        return try? coder.1.decode(LanesFile.self, from: data)
    }

    /// Reads Deck/lanes.json from the Sift folder (called from `sync`).
    func syncLanes(_ folder: URL) {
        guard let data = coordinatedData(folder.appending(path: "Deck/lanes.json")),
              let file = try? Self.coder.1.decode(LanesFile.self, from: data) else { return }
        lanes = file
        try? data.write(to: Self.lanesURL, options: .atomic)
    }
}

struct LanesListView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.lanes?.lanes ?? []) { row in
                    NavigationLink { LanePage(row: row) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(row.lane.name).font(.body.weight(.medium))
                                Spacer()
                                let n = row.picks.filter { !store.isSeen($0.url) }.count
                                if n > 0 { Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                            Text(row.rule).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } footer: {
                Text((store.lanes?.lanes ?? []).isEmpty
                     ? "Make a lane on your Mac: New Lane… in the Feeds part of the sidebar. A lane is a saved rule over your feed items: words, a folder, a theme or a type."
                     : "Lanes are made and changed on your Mac.")
            }
        }
        .navigationTitle("Lanes")
    }
}

struct LanePage: View {
    @Environment(Store.self) private var store
    let row: LanesFile.Row
    @State private var reading: Item?

    var body: some View {
        List {
            Section {
                ForEach(row.picks) { pick in
                    Button { store.setSeen([pick.item], true, mode: "lane"); reading = pick.item } label: {
                        let seen = store.isSeen(pick.url)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .top, spacing: 6) {
                                Text(pick.title).font(.body).fontWeight(seen ? .regular : .semibold)
                                    .foregroundStyle(seen ? .secondary : .primary).lineLimit(3)
                                Spacer(minLength: 6)
                                Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(.top, 7).opacity(seen ? 0 : 1)
                            }
                            Text([pick.feedTitle, pick.date?.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text(row.rule) } footer: {
                Text("That's the lane: the last 14 days of your feeds.").frame(maxWidth: .infinity).padding(.vertical, 16)
            }
        }
        .listStyle(.plain)
        .navigationTitle(row.lane.name)
        .sheet(item: $reading) { ReaderView(item: $0) }
    }
}
