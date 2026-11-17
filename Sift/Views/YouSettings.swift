import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Settings > You (owner, 2026-11-17: "show the user what we know about
/// them BEYOND their interest graph"). Algorithm shows the ranking; this
/// pane shows the person: where saves come from, when and how they read,
/// what they finish and skip, how themes move, the files that hold it and
/// what leaves the Mac. The numbers come from `Profile.build`
/// (Engine/Profile.swift), built when the pane appears.
struct YouSettings: View {
    @Environment(AppModel.self) private var model
    @State private var profile: Profile?
    @State private var building = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Everything here is computed on this Mac from files Sift already keeps. Nothing in it is sent anywhere.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if building { ProgressView().controlSize(.small) }
                    Button("Refresh") { Task { await rebuild() } }.disabled(building)
                }
                if let p = profile {
                    section("At a glance") { glance(p) }
                    section("Where your saves come from") { sources(p) }
                    section("When you read") { when(p) }
                    section("How you read") { how(p) }
                    section("What you finish and skip") { finish(p) }
                    section("Your themes over time") { themes(p) }
                    section("What Sift keeps and where") { files(p) }
                } else {
                    Text("Reading your files…").foregroundStyle(.secondary)
                }
                section("What leaves this Mac") { leaves }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if profile == nil { await rebuild() } }
    }

    private func rebuild() async {
        building = true
        profile = await model.buildProfile()
        building = false
    }

    // MARK: Layout

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func line(_ name: String, _ value: String, _ note: String = "") -> some View {
        GridRow {
            Text(name).fontWeight(.medium)
            Text(value).font(.system(.callout, design: .monospaced))
            Text(note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 1. At a glance

    private func glance(_ p: Profile) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            line("Saved links", "\(p.savedLinks)", "errands, dropped links and merged duplicates left out")
            line("Sources", "\(p.sources)", "places your saves come from")
            line("Themes", "\(p.themes)", "")
            line("Followed feeds", "\(p.followedFeeds)", "your own lists included")
            line("Creators in Your Graph", "\(p.creators)", "hidden ones left out")
            line("Devices", "\(p.devices.count)", p.devices.isEmpty ? "no seen, kept or signals files yet" : p.devices.joined(separator: ", "))
        }
        .font(.callout)
    }

    // MARK: 2. Sources

    private func sources(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if p.bySource.isEmpty {
                note("No saved links yet.")
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(p.bySource) { s in
                        GridRow {
                            Text(s.name)
                            Text("\(s.count)").monospacedDigit().gridColumnAlignment(.trailing)
                            Text(percent(s.count, of: p.savedLinks)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .font(.callout)
            }
            note("Saves per month, the last 12 months. The date is when Sift first saw the link.")
            Chart(p.perMonth) { m in
                BarMark(x: .value("Month", monthLabel(m.month)), y: .value("Saves", m.count))
            }
            .frame(height: 120)
        }
    }

    // MARK: 3. When

    private struct Bar: Identifiable {
        var slot: String
        var device: String
        var count: Int
        var id: String { slot + device }
    }

    private func when(_ p: Profile) -> some View {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var hours: [Bar] = []
        var weekdays: [Bar] = []
        for h in 0..<24 {
            hours.append(Bar(slot: String(format: "%02d", h), device: "Mac", count: p.mac.hours[h]))
            hours.append(Bar(slot: String(format: "%02d", h), device: "iPhone", count: p.phone.hours[h]))
        }
        for d in 0..<7 {
            weekdays.append(Bar(slot: days[d], device: "Mac", count: p.mac.weekdays[d]))
            weekdays.append(Bar(slot: days[d], device: "iPhone", count: p.phone.weekdays[d]))
        }
        return VStack(alignment: .leading, spacing: 10) {
            note("From seen marks and what you did with Today picks: \(p.mac.total) moments on a Mac, \(p.phone.total) on an iPhone. Local time. A seen mark keeps only its newest time, so this leans toward recent reading.")
            if p.mac.total + p.phone.total == 0 {
                note("Nothing yet. Open or mark items as seen and this fills in.")
            } else {
                Text("Hour of day").font(.callout.weight(.medium))
                Chart(hours) { b in
                    BarMark(x: .value("Hour", b.slot), y: .value("Moments", b.count))
                        .foregroundStyle(by: .value("Device", b.device))
                }
                .frame(height: 120)
                Text("Day of week").font(.callout.weight(.medium))
                Chart(weekdays) { b in
                    BarMark(x: .value("Day", b.slot), y: .value("Moments", b.count))
                        .foregroundStyle(by: .value("Device", b.device))
                }
                .frame(height: 110)
            }
        }
    }

    // MARK: 4. How

    private func how(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note("Items you opened, played, kept or marked seen: \(p.opened). The mode is the same Scan, Watch and Read rule the lists use.")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(p.modes) { m in
                    line(m.name, percent(m.count, of: p.opened), "\(m.count) items")
                }
                line("Reading time", p.medianReadMinutes.map { "\($0) min" } ?? "–",
                     p.readSample == 0 ? "no Read item with saved text yet" : "median of \(p.readSample) Read items with text, at \(Modes.wordsPerMinute) words a minute")
                line("Video length", p.medianVideoSeconds.map(duration) ?? "–",
                     p.videoSample == 0 ? "no watched video with a known length yet" : "median of \(p.videoSample) watched videos in your library")
                line("Keep rate in Today", p.keepRate.map { String(format: "%.0f%%", $0 * 100) } ?? "–",
                     "\(p.todayKept) kept of \(p.todayOpened) picks opened, played or kept")
            }
            .font(.callout)
        }
    }

    // MARK: 5. Finish and skip

    private func finish(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            note("Per feed, from what you did with its Today picks on every device. A quick skip is less than 1.5 seconds on screen on the iPhone.")
            if p.feeds.isEmpty {
                note("No signals yet.")
            } else {
                Text("Most kept").font(.callout.weight(.medium))
                habits(p.mostKept, empty: "Nothing kept from Today yet.")
                Text("Most skipped").font(.callout.weight(.medium))
                habits(p.mostSkipped, empty: "No quick skips yet.")
                Text("Every feed with signals").font(.callout.weight(.medium))
                habits(Array(p.feeds.prefix(30)), empty: "")
            }
        }
    }

    private func habits(_ rows: [Profile.FeedHabit], empty: String) -> some View {
        Group {
            if rows.isEmpty {
                note(empty)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        Text("Feed"); Text("Read time"); Text("Opens"); Text("Keeps"); Text("Skips")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(rows) { h in
                        GridRow {
                            Text(h.title).lineLimit(1)
                            Text(duration(Int(h.dwellSeconds.rounded()))).monospacedDigit()
                            Text("\(h.opens)").monospacedDigit()
                            Text("\(h.keeps)").monospacedDigit()
                            Text("\(h.skips)").monospacedDigit()
                        }
                    }
                }
                .font(.callout)
            }
        }
    }

    // MARK: 6. Themes

    private func themes(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note("Saves per theme per month, the last 12 months. Rising or falling compares the last 3 months with the 3 before: a change of at least 2 saves and a quarter.")
            if p.themeTrends.isEmpty {
                note("No themed saves yet.")
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(p.themeTrends) { t in
                        GridRow {
                            Text(t.name).lineLimit(1)
                            spark(t.months)
                            Text("\(t.total)").monospacedDigit()
                            trendLabel(t.trend)
                        }
                    }
                }
                .font(.callout)
            }
        }
    }

    private func spark(_ months: [Int]) -> some View {
        let top = max(1, months.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(months.enumerated()), id: \.offset) { _, n in
                RoundedRectangle(cornerRadius: 1)
                    .fill(n == 0 ? Color.secondary.opacity(0.2) : Color.accentColor)
                    .frame(width: 6, height: max(2, 22 * CGFloat(n) / CGFloat(top)))
            }
        }
        .frame(height: 22, alignment: .bottom)
    }

    @ViewBuilder
    private func trendLabel(_ trend: String) -> some View {
        switch trend {
        case "rising": Label("Rising", systemImage: "arrow.up.right").foregroundStyle(.green)
        case "falling": Label("Falling", systemImage: "arrow.down.right").foregroundStyle(.orange)
        default: Text("Steady").foregroundStyle(.secondary)
        }
    }

    // MARK: 7. Files

    private func files(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note("Plain files you can open without Sift: JSON, Markdown and SQLite.")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(p.files) { f in
                    GridRow {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(f.name).fontWeight(.medium)
                            Text(f.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(f.exists ? ByteCountFormatter.string(fromByteCount: f.bytes, countStyle: .file) : "not there")
                            .monospacedDigit().foregroundStyle(f.exists ? .primary : .secondary)
                        Button("Show in Finder") { show(f.path) }.disabled(!f.exists).controlSize(.small)
                    }
                }
            }
            .font(.callout)
            Button("Export as JSON…") { export(p) }
        }
    }

    private func show(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    private func export(_ p: Profile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Sift profile.json"
        panel.message = "Everything on this pane, as JSON."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        do {
            try e.encode(p).write(to: url, options: .atomic)
        } catch {
            model.exportMessage = "Could not write the file: \(error.localizedDescription)"
        }
    }

    // MARK: 8. What leaves

    private var leaves: some View {
        VStack(alignment: .leading, spacing: 6) {
            note("Your links, titles, text, themes and notes stay on this Mac. Two things leave it. When Telemetry is on, Sift sends one anonymous report a week: app version, kinds of sources and feeds, rough sizes and switches, never a link, title, theme name or file path (Settings > Telemetry shows it). When you sort, discover themes or ask for Farther suggestions, Sift sends titles, links and short previews to Claude through your own login or API key. Page bodies are never sent for sorting. Sift has no account and no server of its own for your library.")
            Text(Telemetry.enabled ? "Telemetry is on." : "Telemetry is off.")
                .font(.callout.weight(.medium))
        }
    }

    // MARK: Formatting

    private func percent(_ n: Int, of total: Int) -> String {
        guard total > 0 else { return "–" }
        return String(format: "%.0f%%", Double(n) / Double(total) * 100)
    }

    private func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return String(format: "%d h %02d min", seconds / 3600, (seconds % 3600) / 60)
    }

    /// "2026-11" → "Nov 26".
    private func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return key }
        let names = Calendar.current.shortMonthSymbols
        return "\(names[(parts[1] - 1 + 12) % 12]) \(String(format: "%02d", parts[0] % 100))"
    }
}
