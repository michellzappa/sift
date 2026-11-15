import SwiftUI

/// The public Community Pulse (`/v1/community`), shown in Settings >
/// Telemetry as Headroom shows its own. Counts are nil when a group is under
/// the Worker's floor. Reading it sends nothing about this Mac.
struct CommunityStats: Decodable, Sendable {
    struct Privacy: Decodable, Sendable {
        let minimumGroupSize: Int
        enum CodingKeys: String, CodingKey { case minimumGroupSize = "minimum_group_size" }
    }
    struct Week: Decodable, Identifiable, Sendable {
        let period: String
        let count: Int?
        let inProgress: Bool
        let newMacs: Int?
        let returningMacs: Int?
        let reactivatedMacs: Int?
        var id: String { period }
        enum CodingKeys: String, CodingKey {
            case period, count
            case inProgress = "in_progress"
            case newMacs = "new_macs"
            case returningMacs = "returning_macs"
            case reactivatedMacs = "reactivated_macs"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            period = try c.decode(String.self, forKey: .period)
            count = try c.decodeIfPresent(Int.self, forKey: .count)
            inProgress = try c.decodeIfPresent(Bool.self, forKey: .inProgress) ?? false
            newMacs = try c.decodeIfPresent(Int.self, forKey: .newMacs)
            returningMacs = try c.decodeIfPresent(Int.self, forKey: .returningMacs)
            reactivatedMacs = try c.decodeIfPresent(Int.self, forKey: .reactivatedMacs)
        }
    }
    struct Item: Decodable, Identifiable, Sendable {
        let name: String
        let count: Int
        var id: String { name }
    }
    struct Feature: Decodable, Identifiable, Sendable {
        let name: String
        let adoption: Int
        var id: String { name }
    }
    struct Release: Decodable, Sendable {
        let version: String
        let published: String?
    }
    struct Latest: Decodable, Sendable {
        let period: String
        let inProgress: Bool
        let reportingMacs: Int?
        let versions: [Item]
        let architectures: [Item]
        let macosMajors: [Item]
        let countries: [Item]
        let sources: [Item]
        let destinations: [Item]
        let backends: [Item]
        let librarySizes: [Item]
        let themeCounts: [Item]
        let features: [Feature]
        let feedKinds: [Item]
        let knownFeeds: [Item]
        let knownFeedMinimum: Int?

        enum CodingKeys: String, CodingKey {
            case period, versions, architectures, countries, sources, destinations, backends, features
            case inProgress = "in_progress"
            case reportingMacs = "reporting_macs"
            case macosMajors = "macos_majors"
            case librarySizes = "library_sizes"
            case themeCounts = "theme_counts"
            case feedKinds = "feed_kinds"
            case knownFeeds = "known_feeds"
            case knownFeedMinimum = "known_feed_minimum_group_size"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func list<T: Decodable>(_ key: CodingKeys) -> [T] { (try? c.decodeIfPresent([T].self, forKey: key)) ?? [] }
            period = try c.decode(String.self, forKey: .period)
            inProgress = (try? c.decodeIfPresent(Bool.self, forKey: .inProgress)) ?? false
            reportingMacs = try? c.decodeIfPresent(Int.self, forKey: .reportingMacs)
            versions = list(.versions); architectures = list(.architectures); macosMajors = list(.macosMajors)
            countries = list(.countries); sources = list(.sources); destinations = list(.destinations)
            backends = list(.backends); librarySizes = list(.librarySizes); themeCounts = list(.themeCounts)
            features = list(.features); feedKinds = list(.feedKinds); knownFeeds = list(.knownFeeds)
            knownFeedMinimum = try? c.decodeIfPresent(Int.self, forKey: .knownFeedMinimum)
        }
    }

    let privacy: Privacy
    let weeklyActiveMacs: [Week]
    let latestRelease: Release?
    let latest: Latest?

    enum CodingKeys: String, CodingKey {
        case privacy, latest
        case weeklyActiveMacs = "weekly_active_macs"
        case latestRelease = "latest_release"
    }

    static var url: URL { Telemetry.communityURL.deletingLastPathComponent().appending(path: "v1/community") }

    static func load() async -> CommunityStats? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(CommunityStats.self, from: data)
    }
}

/// The Community Pulse section for Settings > Telemetry.
struct CommunityPulseSection: View {
    @State private var stats: CommunityStats?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        Section {
            if loading && stats == nil {
                ProgressView("Loading the Community Pulse…").controlSize(.small)
            } else if let stats, let latest = stats.latest {
                pulse(stats, latest)
            } else if failed {
                Text("The Community Pulse could not load. Check your connection and refresh.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No reports yet this week.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                Link("Open the Community Pulse page", destination: Telemetry.communityURL).font(.caption)
            }
        } header: {
            Text("Community Pulse")
        } footer: {
            Text("Totals from every Mac that shares usage counts, published at the link above. Groups under the privacy floor are withheld. Loading this sends nothing about your Mac.")
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        let fresh = await CommunityStats.load()
        if let fresh { stats = fresh }
        failed = fresh == nil
        loading = false
    }

    // MARK: Layout

    @ViewBuilder private func pulse(_ stats: CommunityStats, _ latest: CommunityStats.Latest) -> some View {
        let total = latest.reportingMacs
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                metric("Weekly active Macs", total.map(String.init) ?? "–",
                       latest.inProgress ? "\(latest.period) so far" : latest.period)
                metric("Week over week", deltaLabel(stats.weeklyActiveMacs), "last two complete weeks")
                metric("Latest release", stats.latestRelease?.version ?? "–",
                       stats.latestRelease?.published.map { String($0.prefix(10)) } ?? "")
                metric("Top architecture", latest.architectures.first?.name ?? "–",
                       latest.architectures.first.map { "\($0.count) Macs" } ?? "")
            }
            if latest.inProgress {
                Text("This week is still filling: a Mac reports at its first launch in a week.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            weekly(stats.weeklyActiveMacs)
            cohorts(stats.weeklyActiveMacs)
            versions(latest.versions, release: stats.latestRelease?.version)
            rows("Sources", latest.sources, total)
            rows("Feeds followed", latest.feedKinds.map { .init(name: Self.feedKindName($0.name), count: $0.count) }, total)
            if latest.knownFeeds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Well-known feeds").font(.callout.weight(.medium))
                    Text("Shown once \(latest.knownFeedMinimum ?? 5) or more Macs follow a feed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                rows("Well-known feeds", latest.knownFeeds, total)
            }
            rows("Destinations", latest.destinations, total)
            rows("Sorting", latest.backends.map { .init(name: $0.name == "api" ? "API key" : "Claude Code", count: $0.count) }, total)
            rows("Library size", latest.librarySizes.sorted { Self.rangeStart($0.name) < Self.rangeStart($1.name) }
                .map { .init(name: "\($0.name) links", count: $0.count) }, total)
            rows("macOS", latest.macosMajors.map { .init(name: "macOS \($0.name)", count: $0.count) }, total)
            rows("Countries", latest.countries.map { .init(name: Locale.current.localizedString(forRegionCode: $0.name) ?? $0.name, count: $0.count) }, total)
            features(latest.features)
        }
        .padding(.vertical, 4)
    }

    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func complete(_ weeks: [CommunityStats.Week]) -> [CommunityStats.Week] {
        weeks.filter { !$0.inProgress && $0.period != Telemetry.period() }
    }

    private func deltaLabel(_ weeks: [CommunityStats.Week]) -> String {
        let closed = complete(weeks).compactMap(\.count)
        guard closed.count >= 2 else { return "–" }
        let d = closed[closed.count - 1] - closed[closed.count - 2]
        return d > 0 ? "+\(d)" : "\(d)"
    }

    private func weekly(_ weeks: [CommunityStats.Week]) -> some View {
        let shown = Array(weeks.suffix(16))
        let maximum = max(1, shown.compactMap(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 7) {
            Text("Weekly active Macs").font(.callout.weight(.medium))
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(shown) { w in
                    let partial = w.inProgress || w.period == Telemetry.period()
                    VStack(spacing: 4) {
                        Text(w.count.map(String.init) ?? "·").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(w.count == nil ? Color.primary.opacity(0.12) : Color.primary.opacity(partial ? 0.26 : 0.55))
                            .frame(maxWidth: .infinity, minHeight: 3, maxHeight: 88 * CGFloat(Double(w.count ?? 0) / Double(maximum)))
                        Text(String(w.period.suffix(2))).font(.caption2.monospacedDigit())
                            .foregroundStyle(partial ? .tertiary : .secondary)
                    }
                }
            }
            .frame(height: 118, alignment: .bottom)
        }
    }

    @ViewBuilder private func cohorts(_ weeks: [CommunityStats.Week]) -> some View {
        let closed = complete(weeks)
        if let week = closed.last(where: { $0.newMacs != nil || $0.returningMacs != nil }) {
            let total = Double(max(1, week.count ?? 1))
            VStack(alignment: .leading, spacing: 7) {
                Text("New and returning, \(week.period)").font(.callout.weight(.medium))
                ForEach([("New", week.newMacs), ("Returning", week.returningMacs), ("Back again", week.reactivatedMacs)], id: \.0) { label, value in
                    HStack(spacing: 8) {
                        Text(label).font(.caption).frame(width: 90, alignment: .leading)
                        bar(Double(value ?? 0), total)
                        Text(value.map(String.init) ?? "·").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder private func versions(_ items: [CommunityStats.Item], release: String?) -> some View {
        if !items.isEmpty {
            let sorted = items.sorted { $0.name.compare($1.name, options: .numeric) == .orderedAscending }
            let maximum = max(1, sorted.map(\.count).max() ?? 1)
            let covered = sorted.reduce(0) { $0 + $1.count }
            VStack(alignment: .leading, spacing: 7) {
                Text("Versions").font(.callout.weight(.medium))
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(sorted) { item in
                        let current = item.name == release
                        VStack(spacing: 4) {
                            Text("\(item.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(current ? 0.85 : 0.45))
                                .frame(maxWidth: .infinity, minHeight: 3, maxHeight: 88 * CGFloat(Double(item.count) / Double(maximum)))
                            Text(item.name).font(.caption2.monospacedDigit().weight(current ? .semibold : .regular))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                .frame(height: 118, alignment: .bottom)
                if let release, let on = sorted.first(where: { $0.name == release }), covered > 0 {
                    Text("\(Int((Double(on.count) / Double(covered) * 100).rounded()))% on \(release), the latest release")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func rows(_ title: String, _ items: [CommunityStats.Item], _ total: Int?) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.callout.weight(.medium))
                ForEach(items.sorted { $0.count > $1.count }) { item in
                    HStack(spacing: 8) {
                        Text(item.name).font(.caption).frame(width: 150, alignment: .leading).lineLimit(1)
                        bar(Double(item.count), Double(max(total ?? item.count, 1)))
                        Text("\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder private func features(_ items: [CommunityStats.Feature]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Feature adoption").font(.callout.weight(.medium))
                ForEach(items) { f in
                    HStack(spacing: 8) {
                        Text(Self.featureName(f.name)).font(.caption).frame(width: 150, alignment: .leading).lineLimit(1)
                        bar(Double(f.adoption), 100)
                        Text("\(f.adoption)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func bar(_ value: Double, _ total: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(3, g.size.width * CGFloat(min(value / max(total, 1), 1))))
            }
        }
        .frame(height: 7)
    }

    // MARK: Names

    static func rangeStart(_ s: String) -> Int { Int(s.prefix { $0.isNumber }) ?? 0 }

    static func feedKindName(_ id: String) -> String {
        if id == "web" { return "Web feeds" }
        return FeedProviders.provider(id: id)?.name ?? id
    }

    static func featureName(_ id: String) -> String {
        switch id {
        case "themes": "Themes"
        case "on_device_model": "On-device model"
        case "local_first_pass": "On-device first pass"
        case "local_summaries": "On-device summaries"
        case "youtube_transcripts": "YouTube transcripts"
        case "reel_transcripts": "Reel transcripts"
        case "youtube_audio": "YouTube audio"
        case "connections": "Connections"
        case "close_after_send": "Close after Send"
        default: id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
