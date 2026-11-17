import SwiftUI

/// People: one person, every place they publish (Feeds/People.swift).
/// Follow a person to follow each place that has a feed.
struct PeopleView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?
    @State private var filter = ""
    @State private var onlyMissing = false

    private var shown: [Person] {
        model.people.filter { person in
            (filter.isEmpty || person.name.localizedCaseInsensitiveContains(filter))
                && (!onlyMissing || person.profiles.contains { $0.hasFeed && model.followedFeed(for: $0) == nil })
        }
    }

    var body: some View {
        ReaderSplit(showing: shown.contains { $0.id == selected }) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The people behind your feeds and saves, with every place they publish. Sift finds them from what each person says about themselves: rel=me links and the profiles their own site links to, and a Bluesky handle that is their domain. Follow a person to follow each place that has a feed. One post on several platforms shows once in Today.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                        Toggle("Places not followed", isOn: $onlyMissing)
                        Spacer()
                        if model.isFindingPeople {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Look Again") { model.refreshPeople(force: true) }
                        }
                    }
                    .controlSize(.small)
                }
                .padding(12)
                Divider()
                if shown.isEmpty {
                    ContentUnavailableView(model.isFindingPeople ? "Reading your creators' sites…" : "No people yet",
                                           systemImage: "person.crop.rectangle.stack",
                                           description: Text("Sift checks up to \(People.perRound) of your feeds' sites and Your Graph writers each hour. A person shows here when two or more of their places are found."))
                } else {
                    List(shown, selection: $selected) { person in
                        PersonRow(person: person).tag(person.id)
                            .contextMenu {
                                Button("Follow Everywhere") { model.followPerson(person) }
                                Button("Not One Person") { model.splitPerson(person) }
                            }
                    }
                    .listStyle(.inset)
                }
            }
        } pane: {
            if let p = shown.first(where: { $0.id == selected }) { PersonPane(person: p).id(p.id) }
        }
        .onAppear { model.refreshPeople() }
    }
}

private struct PersonRow: View {
    @Environment(AppModel.self) private var model
    let person: Person

    var body: some View {
        let followed = person.profiles.filter { model.followedFeed(for: $0) != nil }.count
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "person.crop.circle").foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).fontWeight(.medium).lineLimit(1)
                Text(person.profiles.map(\.platformName).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(followed == 0 ? "Not followed" : "\(followed) followed").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct PersonPane: View {
    @Environment(AppModel.self) private var model
    let person: Person
    @State private var working: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Person", systemImage: "person.crop.circle").font(.caption).foregroundStyle(.secondary)
                    Text(person.name).font(.title2.weight(.semibold))
                }
                HStack {
                    let missing = person.profiles.filter { $0.hasFeed && model.followedFeed(for: $0) == nil }
                    Button("Follow Everywhere") { model.followPerson(person) }
                        .buttonStyle(.borderedProminent)
                        .disabled(missing.isEmpty)
                        .help(missing.isEmpty ? "Every place with a feed is followed" : "Follows \(missing.map(\.platformName).joined(separator: ", "))")
                    Button("Not One Person") { model.splitPerson(person) }
                        .help("These places do not belong together. Sift will not group them again.")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Places").font(.headline)
                    ForEach(person.profiles) { p in place(p) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("How Sift knows").font(.headline)
                    ForEach(person.evidence, id: \.self) { Text("• " + $0).font(.callout).foregroundStyle(.secondary) }
                    Text("Only what the person publishes counts. A site that links to many YouTube channels says nothing about which is theirs, so Sift skips it.")
                        .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func place(_ p: Place) -> some View {
        HStack(spacing: 10) {
            Image(systemName: p.symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.platformName).fontWeight(.medium)
                Text(p.handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.followedFeed(for: p) != nil {
                Label("Following", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
            } else if p.hasFeed {
                Button(working.contains(p.id) ? "Following…" : "Follow") {
                    working.insert(p.id)
                    Task {
                        let ok = await model.followProfile(p)
                        working.remove(p.id)
                        model.note(ok ? "Following \(person.name) on \(p.platformName)" : "No feed found for \(p.handle)")
                        model.refreshFeedCounts()
                        model.refreshToday()
                    }
                }
                .disabled(working.contains(p.id))
            } else {
                Text("No feed").font(.caption).foregroundStyle(.tertiary)
            }
            Button { model.openInApp(p.url) } label: { Image(systemName: "arrow.up.forward.square") }
                .buttonStyle(.borderless).help("Open \(p.url)")
        }
    }
}
