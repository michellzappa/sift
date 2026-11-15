import SwiftUI

/// Add a feed from anything: a site, r/swift, @name.bsky.social,
/// @user@mastodon.social, a YouTube channel, "podcast: name", "news: words".
/// The matching provider shows as you type; the providers below are examples.
/// Several results (podcast search, GitHub releases or commits) show as a
/// list to pick from.
struct AddFeedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var finding = false
    @State private var results: [FeedProviders.Found] = []
    @State private var failed = false
    @State private var folder = ""
    @FocusState private var focused: Bool

    private var match: any FeedProvider { FeedProviders.match(input) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Follow").font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                Image(systemName: input.isEmpty ? "plus.magnifyingglass" : match.symbol)
                    .frame(width: 18).foregroundStyle(.secondary)
                TextField("A site, r/subreddit, @name.bsky.social, a YouTube channel, podcast: name…", text: $input)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(find)
                    .onChange(of: input) { _, _ in results = []; failed = false }
                if !input.isEmpty {
                    Text(match.name).font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))

            if finding {
                HStack { ProgressView().controlSize(.small); Text("Looking for the feed…").foregroundStyle(.secondary) }
            } else if failed {
                Text("Sift found no feed for that. Try the site's home page, a profile address, or the feed address itself.")
                    .font(.callout).foregroundStyle(.orange)
            } else if !results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results, id: \.url) { r in result(r) }
                }
                if !model.feedFolders.isEmpty || !folder.isEmpty {
                    Picker("Folder", selection: $folder) {
                        Text("No folder").tag("")
                        ForEach(model.feedFolders, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 280)
                }
            } else {
                providerHints
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Find", action: find)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || finding || Demo.isOn)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear { focused = true }
    }

    private func result(_ r: FeedProviders.Found) -> some View {
        let following = model.state.feeds.contains { $0.url == r.url }
        let provider = FeedProviders.provider(id: r.provider) ?? WebProvider()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: provider.symbol).frame(width: 18).foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.label ?? (r.parsed.title.isEmpty ? r.url : r.parsed.title)).font(.body.weight(.semibold)).lineLimit(1)
                ForEach(r.parsed.entries.prefix(2), id: \.url) { e in
                    Text(e.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(r.url).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if following {
                Label("Following", systemImage: "checkmark").foregroundStyle(.secondary).font(.callout)
            } else {
                Button("Follow") { model.addFeed(r, category: folder.isEmpty ? nil : folder) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
    }

    private var providerHints: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You can follow").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                ForEach(FeedProviders.all, id: \.id) { p in
                    Button { input = p.examples.first ?? "" } label: {
                        HStack(spacing: 6) {
                            Image(systemName: p.symbol).frame(width: 16).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.name).font(.callout)
                                Text(p.examples.first ?? "").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Example: \(p.examples.joined(separator: ", "))")
                }
            }
        }
    }

    private func find() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        finding = true; failed = false; results = []
        Task {
            let found = await FeedProviders.resolve(text)
            guard text == input else { return }
            finding = false
            results = found
            failed = found.isEmpty
        }
    }
}
