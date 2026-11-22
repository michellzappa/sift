import SwiftUI

/// The directory in Follow: who the people you follow vouch for, small web
/// first, built once a week (Feeds/Directory.swift). Finite: it ends.
struct DirectoryList: View {
    @Environment(AppModel.self) private var model
    @State private var followed: Set<String> = []
    @State private var addingList = false
    @State private var listText = ""

    var body: some View {
        let shown = model.directoryShown
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("From the people you follow").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if model.isBuildingDirectory {
                    ProgressView().controlSize(.mini)
                    Text("Asking blogrolls, Substack, Bluesky and Mastodon…").font(.caption).foregroundStyle(.tertiary)
                } else if let built = model.directory.built {
                    Text("This week's list, \(built.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.tertiary)
                    Button("Look Again") { model.refreshDirectory(force: true) }.controlSize(.small).buttonStyle(.link)
                }
            }
            if shown.isEmpty && !model.isBuildingDirectory {
                Text(model.directory.built == nil
                     ? "Sift asks the blogs, newsletters and accounts you follow whom they recommend, and who your Bluesky follows follow. Only their public addresses leave your Mac."
                     : "Nobody new this week.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Directory.groups, id: \.id) { g in
                let rows = shown.filter { $0.group == g.id }
                if !rows.isEmpty {
                    Text(g.title).font(.callout.weight(.semibold)).padding(.top, 2)
                    ForEach(rows) { e in row(e) }
                }
            }
            watchedLists
            Toggle(isOn: Binding(get: { model.state.directoryThemeSearch },
                                 set: { model.state.directoryThemeSearch = $0; model.refreshDirectory(force: true) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Also search by theme names").font(.callout)
                    Text("Sends the names of your 6 biggest themes to Bluesky (starter packs), Apple Podcasts, Hacker News search and ooh.directory. Off by default.")
                        .font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).controlSize(.small)
            if !shown.isEmpty {
                Text("That's all for this week. Each name shows who vouches for it; nothing here is ranked by popularity.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .onAppear { model.refreshDirectory() }
    }

    /// OPML follow lists you watch (issue #45): each feed in them counts as
    /// "In <owner>'s list". Only the list's address leaves the Mac.
    private var watchedLists: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Lists you watch").font(.callout)
            if model.state.watchedLists.isEmpty {
                Text("None").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(model.state.watchedLists, id: \.self) { address in
                HStack(spacing: 3) {
                    Text(Directory.listOwner(address, title: nil)).font(.caption).lineLimit(1)
                    Button { model.unwatchList(address) } label: { Image(systemName: "xmark").font(.caption2) }
                        .buttonStyle(.borderless).help("Stop watching this list")
                }
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                .help(address)
            }
            Button("Add…") { listText = ""; addingList = true }.controlSize(.small).buttonStyle(.link).disabled(Demo.isOn)
            Spacer()
        }
        .alert("Watch a Follow List", isPresented: $addingList) {
            TextField("FeedLand name or OPML address", text: $listText)
            Button("Watch") { if !model.watchList(listText) { model.note("That is not a list address") } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A FeedLand screen name or the address of any OPML list. Each feed in it shows here as \"In their list\". Only the address leaves your Mac.")
        }
    }

    private func row(_ e: DirectoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: e.group == "newsletter" ? "envelope" : e.group == "mastodon" || e.group == "bluesky" ? "bubble.left"
                  : e.group == "podcast" ? "mic" : "globe")
                .foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(e.name).lineLimit(1)
                    if e.smallWeb {
                        Text("Small web").font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.15))).foregroundStyle(.green)
                    }
                }
                Text(e.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !e.description.isEmpty {
                    Text(e.description).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer()
            if followed.contains(e.id) {
                Image(systemName: "checkmark").foregroundStyle(.secondary).font(.caption)
            } else {
                Button("Follow") { followed.insert(e.id); model.followDirectory(e) }.controlSize(.small).disabled(Demo.isOn)
                Button { model.dismissDirectory(e) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).controlSize(.small).help("Not interested. It stays off the list.")
            }
        }
        .help(e.input)
    }
}
