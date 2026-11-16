import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Follow anything: a site, r/swift, @name.bsky.social, @user@mastodon.social,
/// a YouTube channel, "podcast: name", "news: words". Sift looks while you
/// type (after a short pause), starts from an address on the clipboard, and
/// takes a dropped link or OPML file. Each result shows how often the feed
/// posts, when it last did and its newest titles, so you know what you get
/// before you follow. Following keeps the sheet open, with Undo and Show.
struct AddFeedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var finding = false
    @State private var results: [FeedProviders.Found] = []
    @State private var failed = false
    @State private var fromClipboard = false
    @State private var folder = ""
    @State private var newFolder = ""
    @State private var addingFolder = false
    @State private var priority: FeedPriority? = nil
    @State private var quick: Set<String> = []
    @State private var known: [Telemetry.KnownFeed] = []
    @State private var findTask: Task<Void, Never>?
    @State private var dropping = false
    @State private var opml: [OPMLCandidate]?
    @FocusState private var focused: Bool

    private var match: any FeedProvider { FeedProviders.match(input) }
    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Follow").font(.title3.weight(.semibold))
            field
            if fromClipboard && !input.isEmpty {
                Text("From the clipboard").font(.caption).foregroundStyle(.tertiary)
            }

            if finding && results.isEmpty {
                HStack { ProgressView().controlSize(.small); Text("Looking for the feed…").foregroundStyle(.secondary) }
            } else if failed {
                Text("Sift found no feed for that. Try the site's home page, a profile address, or the feed address itself.")
                    .font(.callout).foregroundStyle(.orange)
            } else if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(results, id: \.url) { r in result(r) }
                    }
                }
                .frame(maxHeight: 380)
                options
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        suggestions
                        popular
                        providerHints
                    }
                }
                .frame(maxHeight: 420)
            }

            HStack {
                Text("Drop a link or an OPML file here").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Find") { find(now: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || finding || Demo.isOn)
            }
        }
        .padding(20)
        .frame(width: 580)
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $dropping, perform: drop)
        .sheet(item: Binding(get: { opml.map(FeedSettings.CandidateList.init) }, set: { if $0 == nil { opml = nil } })) { list in
            OPMLImportSheet(candidates: list.items) { picked in
                model.follow(picked)
                opml = nil
            } cancel: { opml = nil }
        }
        .onAppear {
            focused = true
            pasteFromClipboard()
            known = Telemetry.loadKnownFeeds()?.feeds ?? []
        }
        .task {
            guard Telemetry.enabled else { return }
            await Telemetry.refreshKnownFeeds()
            known = Telemetry.loadKnownFeeds()?.feeds ?? []
        }
    }

    // MARK: The field

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: input.isEmpty ? "plus.magnifyingglass" : match.symbol)
                .frame(width: 18).foregroundStyle(.secondary)
            TextField("A site, r/subreddit, @name.bsky.social, a YouTube channel, podcast: name…", text: $input)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { find(now: true) }
                .onChange(of: input) { _, _ in
                    fromClipboard = false
                    find(now: false)
                }
            if finding && !results.isEmpty { ProgressView().controlSize(.small) }
            if !input.isEmpty {
                Text(match.name).font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                Button { input = ""; results = []; failed = false } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
    }

    // MARK: Results

    private func result(_ r: FeedProviders.Found) -> some View {
        let feed = model.state.feeds.first { $0.url == r.url }
        let provider = FeedProviders.provider(id: r.provider) ?? WebProvider()
        let title = r.label ?? (r.parsed.title.isEmpty ? r.url : r.parsed.title)
        let entries = r.parsed.entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: provider.symbol).frame(width: 18).foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1)
                Text(Self.cadence(r.parsed.entries)).font(.caption).foregroundStyle(.secondary)
                ForEach(entries.prefix(3), id: \.url) { e in
                    HStack(spacing: 6) {
                        Text(FeedParser.Text.title(e.title, body: e.summary))
                            .font(.callout).lineLimit(1)
                        if let date = e.date {
                            Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                Text(r.url).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let feed {
                VStack(alignment: .trailing, spacing: 6) {
                    Label("Following", systemImage: "checkmark").foregroundStyle(.secondary).font(.callout)
                    HStack(spacing: 6) {
                        Button("Undo") { model.removeFeed(feed) }.controlSize(.small)
                        Button("Show") { model.navigationRequest = feed.mine == true ? .source(AppModel.listPrefix + feed.id) : .feed(feed.id); dismiss() }.controlSize(.small)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    // A playlist is usually your own picks: Library, not Today.
                    if URL(string: r.url).flatMap(YouTubePlaylist.id(inFeed:)) != nil {
                        Button("Add to Library") {
                            model.addFeed(r, category: chosenFolder, priority: priority, mine: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Your own playlist: its videos go to your Library, like Watch Later.")
                        Button("Follow in Today") { model.addFeed(r, category: chosenFolder, priority: priority) }
                            .controlSize(.small)
                            .help("Someone else's playlist: new videos show in Today.")
                    } else {
                        Button("Follow") {
                            model.addFeed(r, category: chosenFolder, priority: priority)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(Demo.isOn)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
    }

    /// "About 3 posts a week · last post 2 days ago".
    static func cadence(_ entries: [FeedEntry], now: Date = Date()) -> String {
        let dates = entries.compactMap(\.date).filter { $0 <= now.addingTimeInterval(3600) }.sorted(by: >)
        guard let last = dates.first else {
            return entries.isEmpty ? "No posts yet" : "\(entries.count) items, no dates"
        }
        let span = max(now.timeIntervalSince(dates.last ?? last) / 86_400, 1)
        let perDay = Double(dates.count) / span
        let rate: String
        if dates.count < 2 { rate = "One post so far" }
        else if perDay >= 1.5 { rate = "About \(Int(perDay.rounded())) posts a day" }
        else if perDay * 7 >= 1.5 { rate = "About \(Int((perDay * 7).rounded())) posts a week" }
        else if perDay * 30 >= 1.5 { rate = "About \(Int((perDay * 30).rounded())) posts a month" }
        else { rate = "A few posts a year" }
        let ago = RelativeDateTimeFormatter().localizedString(for: last, relativeTo: now)
        return "\(rate) · last post \(ago)"
    }

    /// Folder and Today priority for the next Follow.
    private var options: some View {
        HStack(spacing: 16) {
            if addingFolder {
                TextField("New folder", text: $newFolder)
                    .textFieldStyle(.roundedBorder).frame(width: 180)
                    .onSubmit { addingFolder = false; folder = newFolder.trimmingCharacters(in: .whitespaces) }
            } else {
                Picker("Folder", selection: $folder) {
                    Text("No folder").tag("")
                    ForEach(Array(Set(model.feedFolders + (folder.isEmpty ? [] : [folder]))).sorted(), id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("New Folder…").tag("\u{0}new")
                }
                .frame(maxWidth: 240)
                .onChange(of: folder) { _, value in
                    if value == "\u{0}new" { folder = ""; newFolder = ""; addingFolder = true }
                }
            }
            Picker("In Today", selection: $priority) {
                Text("Auto").tag(FeedPriority?.none)
                ForEach(FeedPriority.allCases, id: \.self) { Text($0.label).tag(FeedPriority?.some($0)) }
            }
            .frame(maxWidth: 220)
        }
    }

    private var chosenFolder: String? {
        let f = addingFolder ? newFolder.trimmingCharacters(in: .whitespaces) : folder
        return f.isEmpty ? nil : f
    }

    // MARK: Before typing

    /// Feeds from what you already save, with the evidence. One click follows.
    @ViewBuilder private var suggestions: some View {
        let list = model.feedSuggestions
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested from what you save").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(list.prefix(8)) { s in
                    HStack(spacing: 8) {
                        Image(systemName: FeedProviders.provider(id: s.providerID)?.symbol ?? "globe")
                            .frame(width: 16).foregroundStyle(.secondary)
                        Button(s.label) { input = s.input; find(now: true) }.buttonStyle(.plain).lineLimit(1)
                        Text(s.evidence).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        quickFollow(s.input)
                    }
                }
            }
        }
    }

    /// Large public feeds from Sift's list (the same list the usage counts
    /// use), minus the ones you follow.
    @ViewBuilder private var popular: some View {
        let followedHosts = Set(model.state.feeds.compactMap { Telemetry.feedKey($0.url) })
        let list = known.filter { k in !k.match.contains { p in followedHosts.contains { Telemetry.matches($0, p) } } }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Popular").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                    ForEach(list.prefix(16), id: \.id) { k in
                        let address = k.match.first.map { "https://" + $0 } ?? ""
                        HStack(spacing: 6) {
                            Button(k.name) { input = address; find(now: true) }.buttonStyle(.plain).lineLimit(1)
                            Spacer()
                            quickFollow(address)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func quickFollow(_ address: String) -> some View {
        if quick.contains(address) {
            Image(systemName: "checkmark").foregroundStyle(.secondary).font(.caption)
        } else {
            Button("Follow") { quick.insert(address); model.followQuick(address) }
                .controlSize(.small).disabled(Demo.isOn)
        }
    }

    private var providerHints: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You can follow").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                ForEach(FeedProviders.all, id: \.id) { p in
                    Button { input = p.examples.first ?? ""; focused = true } label: {
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

    // MARK: Finding

    /// `now` for Return, Find and clicks; otherwise a pause after typing, and
    /// only for input that looks complete (an address, a handle, r/…).
    private func find(now: Bool) {
        findTask?.cancel()
        let text = trimmed
        results = []; failed = false
        guard !text.isEmpty, !Demo.isOn else { finding = false; return }
        if !now && !Self.looksComplete(text) { finding = false; return }
        findTask = Task {
            if !now { try? await Task.sleep(for: .milliseconds(700)) }
            guard !Task.isCancelled else { return }
            finding = true
            let found = await FeedProviders.resolve(text)
            guard !Task.isCancelled, text == trimmed else { return }
            finding = false
            results = found
            failed = found.isEmpty
        }
    }

    static func looksComplete(_ s: String) -> Bool {
        if s.count < 4 { return false }
        if s.contains("://") { return true }
        if s.hasPrefix("r/") || s.hasPrefix("@") || s.contains(":") { return s.count >= 5 }
        let parts = s.split(separator: ".")
        return parts.count >= 2 && (parts.last?.count ?? 0) >= 2 && !s.contains(" ")
    }

    private func pasteFromClipboard() {
        guard input.isEmpty, let s = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), s.count < 500, !s.contains("\n") else { return }
        let isAddress = (s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("feed:")) && URL(string: s) != nil
        let isHandle = s.hasPrefix("r/") || (s.hasPrefix("@") && s.contains("."))
        guard isAddress || isHandle else { return }
        input = s
        fromClipboard = true
        find(now: true)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let item = providers.first else { return false }
        if item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.isFileURL {
                        opml = model.readOPML(url)
                    } else {
                        input = url.absoluteString; find(now: true)
                    }
                }
            }
            return true
        }
        _ = item.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in input = url.absoluteString; find(now: true) }
        }
        return true
    }
}
