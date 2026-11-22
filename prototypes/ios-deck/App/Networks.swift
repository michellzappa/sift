import SwiftUI

// Network dials on the phone (issue #40). The Mac holds the dials and the
// learning (Sift/Engine/NetworkDial.swift, compiled into this app too) and
// writes them into creators.json (`networks`). The phone sets a dial with a
// follows/ request of kind "network" (input = network id, priority = dial).

extension Store {
    /// The dial the Mac has, or the one this phone asked for last.
    func networkDial(_ id: String) -> NetworkDial {
        if let r = feedRequests.last(where: { $0.kind == "network" && $0.input == id }), macFeeds?.requests[r.id] == nil {
            return NetworkDial(r.priority)
        }
        return NetworkDial(creators?.networks?.first { $0.id == id }?.dial)
    }

    func setNetworkDial(_ d: NetworkDial, network id: String) { request("network", input: id, priority: d.rawValue) }

    /// True while a dial change waits for the Mac.
    func networkPending(_ id: String) -> Bool {
        feedRequests.contains { $0.kind == "network" && $0.input == id && macFeeds?.requests[$0.id] == nil }
    }
}

/// One dial per network, with what Sift learned beside it.
struct NetworksView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            let rows = (store.creators?.networks ?? []).filter { Network(rawValue: $0.id) != nil }
            if rows.isEmpty {
                Text("Your Mac has not shared its networks yet. Open Sift on the Mac with feeds followed.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.id) { row in
                let item = (network: Network(rawValue: row.id) ?? .blogs, row: row)
                Section {
                    Picker("In Today", selection: Binding(get: { store.networkDial(item.row.id) },
                                                          set: { store.setNetworkDial($0, network: item.row.id) })) {
                        ForEach(NetworkDial.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.row.stats.summary(item.network)).font(.subheadline)
                        Text(item.row.stats.learnedText).font(.caption).foregroundStyle(.secondary)
                        if store.networkPending(item.row.id) {
                            Text("Waiting for your Mac").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("\(item.network.title) · \(item.row.feeds == 1 ? "1 feed" : "\(item.row.feeds) feeds")", systemImage: item.network.symbol)
                } footer: {
                    Text(store.networkDial(item.row.id).help)
                }
            }
            Section {
            } footer: {
                Text("How much of Today each network gets. Sift also learns from what you open, keep and skip per network in the last \(Int(NetworkStats.days)) days, and moves its score by up to \(Int(NetworkDial.learnedWeight * 100))%. Your Mac does the ranking.")
            }
        }
        .navigationTitle("Networks")
    }
}
