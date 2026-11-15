import SwiftUI

// Version history, from the CHANGELOG.md that ships in the app. Ported from
// Headroom (Shared/Changelog.swift, Shared/ChangelogView.swift). The same
// file gives the GitHub release notes (scripts/changelog-section.sh), so the
// app and the release page never disagree.

struct ChangelogVersion: Equatable, Identifiable, Sendable {
    var version: String
    /// ISO date from the heading, e.g. 2026-11-15.
    var date: String?
    var sections: [ChangelogSection]
    var id: String { version }

    /// "0.5.1 · 15 Nov 2026". No dashes in what the user reads.
    var title: String {
        guard let date, let d = Self.day(date) else { return version }
        return "\(version) · \(d.formatted(date: .abbreviated, time: .omitted))"
    }

    /// YYYY-MM-DD as a date at noon, so no time zone moves it a day.
    private static func day(_ s: String) -> Date? {
        let n = s.split(separator: "-").compactMap { Int($0) }
        guard n.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: n[0], month: n[1], day: n[2], hour: 12))
    }
}

struct ChangelogSection: Equatable, Sendable {
    var title: String
    var items: [String]
}

enum Changelog {
    static let githubURL = URL(string: "https://github.com/michellzappa/sift/blob/main/CHANGELOG.md")!

    static func load(from bundle: Bundle = .main) -> [ChangelogVersion] {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// `## X.Y.Z - YYYY-MM-DD` (or an em dash) starts a version, `### Group`
    /// a group, `- ` an item. Soft-wrapped item lines join into one. Text
    /// above the first version is release process and is skipped.
    static func parse(_ markdown: String) -> [ChangelogVersion] {
        var versions: [ChangelogVersion] = []
        var current: ChangelogVersion?
        var section: ChangelogSection?
        var item: String?

        func flushItem() {
            if let text = item?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                if section == nil { section = ChangelogSection(title: "", items: []) }
                section?.items.append(text)
            }
            item = nil
        }
        func flushSection() {
            flushItem()
            if let s = section, !s.items.isEmpty { current?.sections.append(s) }
            section = nil
        }
        func flushVersion() {
            flushSection()
            if let v = current { versions.append(v) }
            current = nil
        }

        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flushVersion()
                let heading = String(line.dropFirst(3))
                let version = heading.prefix { $0.isNumber || $0 == "." }
                let date = heading.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression).map { String(heading[$0]) }
                current = ChangelogVersion(version: version.isEmpty ? heading : String(version), date: date, sections: [])
            } else if current == nil {
                continue
            } else if line.hasPrefix("### ") {
                flushSection()
                section = ChangelogSection(title: String(line.dropFirst(4)), items: [])
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushItem()
                item = String(line.dropFirst(2))
            } else if line.isEmpty {
                flushItem()
            } else if item != nil {
                item! += " " + line
            } else {
                item = line
            }
        }
        flushVersion()
        return versions
    }
}

/// Every release, newest first. Used by the Version History window and by
/// Settings > About.
struct ChangelogView: View {
    var versions: [ChangelogVersion] = Changelog.load()

    var body: some View {
        if versions.isEmpty {
            ContentUnavailableView {
                Label("No version history in this build", systemImage: "doc.text")
            } actions: {
                Link("Version History on GitHub", destination: Changelog.githubURL)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(versions) { version in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(version.title).font(.title3.weight(.semibold))
                                if version.version == UpdateCheck.installedVersion {
                                    Text("This version")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                        .foregroundStyle(.tint)
                                }
                            }
                            ForEach(Array(version.sections.enumerated()), id: \.offset) { _, section in
                                VStack(alignment: .leading, spacing: 6) {
                                    if !section.title.isEmpty {
                                        Text(section.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                    }
                                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•").foregroundStyle(.secondary)
                                            Text(Self.markdown(item))
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

enum VersionHistory {
    static let windowID = "version-history"
}
