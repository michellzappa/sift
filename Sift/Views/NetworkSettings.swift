import SwiftUI

/// Network dials (Engine/NetworkDial.swift, issue #40): one row per network
/// with its dial and what Sift learned from use. Settings > Algorithm.
struct NetworkDialsSection: View {
    @Environment(AppModel.self) private var model
    @State private var stats: [Network: NetworkStats] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How much of Today each network gets. More: score × 1.5 and up to \(NetworkDial.morePerFeed) unseen items per feed. Less: score × 0.5, 1 item per feed and no extra slots. Off: none, Don't Miss feeds too. Beside each dial is what Sift learned from what you open, keep and skip in the last \(Int(NetworkStats.days)) days, on this Mac and your iPhone. It moves the score by up to \(Int(NetworkDial.learnedWeight * 100))%.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            let networks = model.networksInUse
            if networks.isEmpty {
                Text("Follow feeds to set their networks here.").foregroundStyle(.secondary)
            } else {
                let counts = model.feedsPerNetwork
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    ForEach(networks) { n in
                        let s = stats[n] ?? .empty
                        GridRow {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.title).fontWeight(.medium)
                                    Text(counts[n, default: 0] == 1 ? "1 feed" : "\(counts[n, default: 0]) feeds")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: n.symbol) }
                            Picker(n.title, selection: Binding(get: { model.networkDial(n) }, set: { model.setNetworkDial($0, for: n) })) {
                                ForEach(NetworkDial.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.segmented).fixedSize()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.summary(n))
                                Text(s.learnedText).foregroundStyle(.secondary)
                            }
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .onAppear { stats = model.networkStats() }
        .onChange(of: model.todayPicks.map(\.url)) { stats = model.networkStats() }
    }
}

/// The network dials as a compact menu for Today's toolbar.
struct NetworkDialMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.networksInUse) { n in
                Picker(selection: Binding(get: { model.networkDial(n) }, set: { model.setNetworkDial($0, for: n) })) {
                    ForEach(NetworkDial.allCases) { Text($0.title).tag($0) }
                } label: {
                    let d = model.networkDial(n)
                    Label(d == .normal ? n.title : "\(n.title): \(d.title)", systemImage: n.symbol)
                }
                .pickerStyle(.menu)
            }
            Divider()
            Button("What Sift Learned…") { model.showHowToday = true }
        } label: {
            Label("Networks", systemImage: "dial.medium")
        }
        .help("How much of Today each network gets: More, Normal, Less or Off")
    }
}
