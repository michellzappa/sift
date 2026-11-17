import SwiftUI

/// The directory in Follow: who the people you follow vouch for, small web
/// first, built once a week (Feeds/Directory.swift). Finite: it ends.
struct DirectoryList: View {
    @Environment(AppModel.self) private var model
    @State private var followed: Set<String> = []

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
                     ? "Sift asks the blogs, newsletters and accounts you follow whom they recommend. Only their public addresses leave your Mac."
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
            if !shown.isEmpty {
                Text("That's all for this week. Each name shows who vouches for it; nothing here is ranked by popularity.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .onAppear { model.refreshDirectory() }
    }

    private func row(_ e: DirectoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: e.group == "newsletter" ? "envelope" : e.group == "mastodon" ? "bubble.left" : "globe")
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
