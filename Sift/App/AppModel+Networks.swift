import Foundation

/// Network dials (Engine/NetworkDial.swift, issue #40): one dial per network
/// that brings items into Today, and what Sift learned from use beside it.
extension AppModel {
    /// The network of a feed, from its provider.
    func network(of feed: Feed) -> Network {
        Network.of(provider: feed.provider ?? AppModel.providerID(forFeed: feed.url))
    }

    /// Feed id → network, for every followed feed.
    var networkOfFeed: [String: Network] {
        Dictionary(state.feeds.map { ($0.id, network(of: $0)) }, uniquingKeysWith: { a, _ in a })
    }

    func networkDial(_ n: Network) -> NetworkDial { NetworkDial(state.networkDials[n.rawValue]) }

    var networkDials: [Network: NetworkDial] {
        Dictionary(uniqueKeysWithValues: Network.allCases.map { ($0, networkDial($0)) })
    }

    /// Sets a network's dial and builds Today again.
    func setNetworkDial(_ dial: NetworkDial, for n: Network) {
        guard networkDial(n) != dial else { return }
        if dial == .normal { state.networkDials.removeValue(forKey: n.rawValue) } else { state.networkDials[n.rawValue] = dial.rawValue }
        refreshToday(force: true)
        writeCreatorsForPhone()
    }

    /// Networks with a followed feed in Today, plus any with a dial set, in
    /// the order of `Network.allCases`.
    var networksInUse: [Network] {
        let used = Set(offeredFeeds.filter(\.enabled).map { network(of: $0) })
        return Network.allCases.filter { used.contains($0) || networkDial($0) != .normal }
    }

    /// Followed feeds per network.
    var feedsPerNetwork: [Network: Int] {
        Dictionary(grouping: offeredFeeds.filter(\.enabled), by: { network(of: $0) }).mapValues(\.count)
    }

    /// What Sift learned per network: signals of the last 30 days and the
    /// Today picks you saw without one.
    func networkStats(events: [SignalEvent]? = nil) -> [Network: NetworkStats] {
        let byFeed = networkOfFeed
        let seen = todayPicks.filter { isSeen($0.url) }.map { p in
            (url: p.url, network: p.why?.network.flatMap(Network.init(rawValue:)) ?? byFeed[p.feedID] ?? Network.of(url: p.url))
        }
        return FeedSignals.networks(events ?? signalEvents(), networkOf: byFeed, seenPicks: seen)
    }
}
