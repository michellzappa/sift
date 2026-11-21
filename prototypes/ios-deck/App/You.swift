import SwiftUI

// Settings > You on the phone: what Sift knows about you beyond your themes.
// The Mac builds it (Sift/Engine/Profile.swift, compiled here too) and
// writes iCloud Drive/Sift/Deck/you.json once a day.

extension Store {
    static var youURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "you.json")
    }

    static func loadYou() -> Profile? {
        guard let data = try? Data(contentsOf: youURL) else { return nil }
        return try? coder.1.decode(Profile.self, from: data)
    }

    func syncYou(_ folder: URL) {
        guard let data = coordinatedData(folder.appending(path: "Deck/you.json")),
              let p = try? Self.coder.1.decode(Profile.self, from: data) else { return }
        you = p
        try? data.write(to: Self.youURL, options: .atomic)
    }
}

struct YouView: View {
    @Environment(Store.self) private var store

    var body: some View {
        List {
            if let p = store.you {
                Section {
                    Text("Built on your Mac from files Sift keeps, \(p.generated.formatted(.relative(presentation: .named))). Nothing in it is sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("At a glance") {
                    row("Saved links", "\(p.savedLinks)")
                    row("Sources", "\(p.sources)")
                    row("Themes", "\(p.themes)")
                    row("Feeds you follow", "\(p.followedFeeds)")
                    row("Creators in Your Graph", "\(p.creators)")
                }
                Section("Where your saves come from") {
                    ForEach(p.bySource.prefix(8)) { row($0.name, "\($0.count)") }
                }
                Section("When you read") {
                    bars(zip(p.mac.hours, p.phone.hours).map { $0 + $1 }, labels: ["0", "6", "12", "18"])
                    Text("Hour of day, Mac and iPhone together. Each link counts once, at its newest mark.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("How you read") {
                    ForEach(p.modes) { row($0.name, "\($0.count)") }
                    if let m = p.medianReadMinutes { row("Typical read", "\(m) min") }
                    if let s = p.medianVideoSeconds { row("Typical video", "\(max(1, s / 60)) min") }
                    if let k = p.keepRate { row("Kept from Today", String(format: "%.0f%%", k * 100)) }
                }
                if !p.mostKept.isEmpty {
                    Section("What you keep") { ForEach(p.mostKept) { row($0.title, "\($0.keeps) kept") } }
                }
                if !p.mostSkipped.isEmpty {
                    Section("What you skip") { ForEach(p.mostSkipped) { row($0.title, "\($0.skips) skipped") } }
                }
                Section("Your themes") {
                    ForEach(p.themeTrends.prefix(12)) { t in
                        row(t.name, t.trend.isEmpty ? "\(t.total)" : "\(t.trend) · \(t.total)")
                    }
                }
            } else {
                ContentUnavailableView("Not here yet", systemImage: "person.text.rectangle",
                                       description: Text("Your Mac writes this once a day after Sift runs there."))
            }
        }
        .navigationTitle("You")
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name).lineLimit(1); Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }

    private func bars(_ values: [Int], labels: [String]) -> some View {
        let top = max(values.max() ?? 1, 1)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.7))
                        .frame(height: max(2, CGFloat(v) / CGFloat(top) * 60))
                }
            }
            .frame(height: 60)
            HStack { ForEach(labels, id: \.self) { Text($0).font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading) } }
        }
        .padding(.vertical, 4)
    }
}
