import SwiftUI

// Who you follow (issue #39) and the Downloads watcher and monthly reminder
// (issue #43). Data and actions: App/AppModel+Following.swift,
// App/AppModel+Downloads.swift, Storage/FollowingReader.swift.

/// Settings > Inputs: one row per network with the date of its data and
/// the export path or handle.
struct FollowingSettings: View {
    @Environment(AppModel.self) private var model
    @State private var bluesky = ""
    @State private var mastodon = ""

    var body: some View {
        Section {
            ForEach(FollowNetwork.allCases) { n in row(n) }
            Toggle("Follow the accounts that have a feed (YouTube, Bluesky, Mastodon)", isOn: .init(
                get: { model.state.following.followAsFeeds },
                set: { model.state.following.followAsFeeds = $0; if $0 { model.followImported() } }
            ))
            Toggle("Watch Downloads for new exports", isOn: .init(
                get: { model.state.following.watchDownloads },
                set: { model.setWatchDownloads($0) }
            ))
            .disabled(Demo.isOn)
        } header: {
            Text("Who you follow")
        } footer: {
            Text("Sift reads whom you follow from each network's own export, and from Bluesky and Mastodon with your handle. It never signs in to Instagram, TikTok or X. Sift follows each account that has a feed once, in a folder per network. If you unfollow one, Sift does not follow it again. You can see every account in Your Graph > People > Who you follow. With Watch Downloads on, Sift copies a new export from Downloads and reads it. The file in Downloads stays where it is. macOS asks once for access to Downloads. Once a month, Sift reminds you about an export that is more than 30 days old.")
                .foregroundStyle(.secondary)
        }
        .onAppear {
            bluesky = model.state.following.blueskyHandle
            mastodon = model.state.following.mastodonHandle
        }
    }

    @ViewBuilder private func row(_ n: FollowNetwork) -> some View {
        let f = model.follows(n)
        StatusRow(icon: n.symbol, name: n.name, status: model.followingStatus(n),
                  warning: model.isStale(n) || (f?.error != nil && f?.accounts.isEmpty == true)) {
            switch n {
            case .bluesky: handleField("@name.bsky.social", text: $bluesky, network: n)
            case .mastodon: handleField("@name@mastodon.social", text: $mastodon, network: n)
            case .instagram, .tiktok:
                Button("Choose…") { model.chooseExport(n) }
            case .youtube, .x:
                Button("Choose…") { model.chooseExport(n) }
                if model.followingSource(n) != nil { Button("Remove") { model.clearFollowing(n) } }
            }
        }
        if n.isExport, let path = model.followingSource(n) {
            LabeledContent("Export") {
                Text(abbreviated(path)).lineLimit(1).truncationMode(.middle)
            }
        }
        if model.isStale(n) {
            Text("This export is more than 30 days old. " + n.exportSteps)
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        } else if n.isExport, model.followingSource(n) == nil {
            Text(n.exportSteps).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func handleField(_ prompt: String, text: Binding<String>, network n: FollowNetwork) -> some View {
        HStack {
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder).frame(width: 200)
                .onSubmit { read(n, text.wrappedValue) }
            Button("Read") { read(n, text.wrappedValue) }
                .disabled(Demo.isOn || model.isReadingFollowing)
        }
    }

    private func read(_ n: FollowNetwork, _ handle: String) {
        let h = handle.trimmingCharacters(in: .whitespaces)
        if n == .bluesky { model.state.following.blueskyHandle = h } else { model.state.following.mastodonHandle = h }
        model.refreshFollowing(force: true)
    }
}

/// The monthly reminder for a stale export, in the sidebar's Library box.
struct ExportReminderRow: View {
    @Environment(AppModel.self) private var model
    @State private var showSteps = false

    var body: some View {
        if let n = model.exportReminder {
            VStack(alignment: .leading, spacing: 4) {
                Label(model.exportAgeDays(n).map { "Your \(n.name) data is \($0) days old" } ?? "Your \(n.name) data is old",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button("How to Export") { showSteps = true }
                        .popover(isPresented: $showSteps) {
                            Text(n.exportSteps + (model.state.following.watchDownloads
                                ? " When the zip is in Downloads, Sift reads it."
                                : " Then choose the zip in Settings > Inputs, or turn on Watch Downloads there."))
                                .padding().frame(width: 300).fixedSize(horizontal: false, vertical: true)
                        }
                    Button("Choose…") { model.chooseExport(n) }
                    Spacer()
                    Button("Later") { model.exportReminder = nil }
                }
                .controlSize(.mini)
            }
        }
    }
}

/// Your Graph > People > Who You Follow: every account from the following
/// lists, by network.
struct FollowingList: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var working: Set<String> = []

    var body: some View {
        let networks = FollowNetwork.allCases.filter { !(model.follows($0)?.accounts.isEmpty ?? true) }
        if networks.isEmpty {
            ContentUnavailableView("No following lists yet", systemImage: "person.2",
                                   description: Text("Add your exports and handles in Settings > Inputs > Who you follow."))
        } else {
            VStack(spacing: 0) {
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    .controlSize(.small).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                List {
                    ForEach(networks) { n in
                        let all = model.follows(n)?.accounts ?? []
                        let shown = filter.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(filter) || $0.place.handle.localizedCaseInsensitiveContains(filter) }
                        Section("\(n.name) · \(all.count)") {
                            ForEach(shown) { a in row(a) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder private func row(_ a: FollowedAccount) -> some View {
        HStack(spacing: 8) {
            Image(systemName: a.place.symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name).lineLimit(1)
                if a.name != a.place.handle, !a.place.handle.hasPrefix("UC") {
                    Text(a.place.handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if model.followedFeed(for: a.place) != nil {
                Text("Following").font(.caption).foregroundStyle(.secondary)
            } else if a.place.hasFeed {
                Button(working.contains(a.id) ? "Following…" : "Follow") {
                    working.insert(a.id)
                    Task {
                        let ok = await model.followProfile(a.place)
                        working.remove(a.id)
                        model.note(ok ? "Following \(a.name)" : "No feed found for \(a.name)")
                        model.refreshFeedCounts()
                        model.refreshToday()
                    }
                }
                .controlSize(.small).disabled(working.contains(a.id))
            } else {
                Text("No feed").font(.caption).foregroundStyle(.tertiary)
            }
            Button { model.openInApp(a.place.url) } label: { Image(systemName: "arrow.up.forward.square") }
                .buttonStyle(.borderless).help("Open \(a.place.url)")
        }
    }
}
