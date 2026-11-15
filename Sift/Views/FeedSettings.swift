import SwiftUI

/// Settings > Inputs > Feeds: import OPML (all or a subset), add a feed by
/// address, the followed feeds with their state, export OPML.
struct FeedSettings: View {
    @Environment(AppModel.self) private var model
    @State private var candidates: [OPMLCandidate]?
    @State private var adding = false
    @State private var showList = false

    var body: some View {
        Section {
            LabeledContent("Feeds") {
                Text(model.state.feeds.isEmpty ? "None yet" : "\(model.state.feeds.count) followed · \(model.feedCount) items")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Import OPML…") { candidates = model.readOPML() }
                Button("Add Feed…") { adding = true }
                if !model.state.feeds.isEmpty {
                    Button("Check Now") { Task { await model.fetchFeeds(force: true) } }
                        .disabled(model.isFetchingFeeds || Demo.isOn)
                    Button("Export OPML…") { model.exportOPML() }
                }
            }
            if !model.state.feeds.isEmpty {
                DisclosureGroup("Followed feeds", isExpanded: $showList) {
                    ForEach(model.state.feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) { feed in
                        FeedRow(feed: feed)
                    }
                }
            }
        } header: {
            Text("Feeds")
        } footer: {
            Text("Blogs, newsletters and sites with an RSS, Atom or JSON feed. Sift checks each feed about once an hour, one site at a time, keeps 90 days of items in Application Support/Sift/feeds, and treats them like any other link: saved text, themes, seen and search. Export OPML takes your feeds to any other reader.")
                .foregroundStyle(.secondary)
        }
        .sheet(item: Binding(get: { candidates.map(CandidateList.init) }, set: { if $0 == nil { candidates = nil } })) { list in
            OPMLImportSheet(candidates: list.items) { picked in
                model.follow(picked)
                candidates = nil
            } cancel: { candidates = nil }
        }
        .sheet(isPresented: $adding) { AddFeedSheet() }
    }

    private struct CandidateList: Identifiable {
        let items: [OPMLCandidate]
        var id: Int { items.count }
    }
}

private struct FeedRow: View {
    @Environment(AppModel.self) private var model
    let feed: Feed

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { feed.enabled }, set: { model.setFeed(feed, enabled: $0) }))
                .labelsHidden().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text(feed.title).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(feed.lastError == nil ? Color.secondary : Color.orange).lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) { model.removeFeed(feed) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Stop following \(feed.title). Its items leave the Feeds list; links already in your library stay.")
        }
    }

    private var status: String {
        if let e = feed.lastError { return e }
        let count = FeedStore.entries(feed.id).count
        let when = feed.lastFetched.map { "checked \($0.formatted(.relative(presentation: .named)))" } ?? "not checked yet"
        return [feed.category, "\(count) items", when].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The feeds in an OPML file, grouped by folder, with checkboxes. All are
/// picked at first; Select None, a folder's own switch or a search narrows it.
struct OPMLImportSheet: View {
    let candidates: [OPMLCandidate]
    let follow: ([OPMLCandidate]) -> Void
    let cancel: () -> Void
    @State private var picked: Set<String>
    @State private var filter = ""

    init(candidates: [OPMLCandidate], follow: @escaping ([OPMLCandidate]) -> Void, cancel: @escaping () -> Void) {
        self.candidates = candidates
        self.follow = follow
        self.cancel = cancel
        _picked = State(initialValue: Set(candidates.filter { !$0.alreadyFollowed }.map(\.url)))
    }

    private var groups: [(name: String, items: [OPMLCandidate])] {
        let shown = filter.isEmpty ? candidates : candidates.filter {
            $0.title.localizedCaseInsensitiveContains(filter) || $0.url.localizedCaseInsensitiveContains(filter)
                || ($0.category ?? "").localizedCaseInsensitiveContains(filter)
        }
        return Dictionary(grouping: shown, by: { $0.category ?? "No folder" })
            .map { ($0.key, $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Feeds").font(.headline)
                Spacer()
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .padding()
            Divider()
            List {
                ForEach(groups, id: \.name) { group in
                    Section {
                        ForEach(group.items) { c in
                            Toggle(isOn: Binding(get: { picked.contains(c.url) }, set: { on in
                                if on { picked.insert(c.url) } else { picked.remove(c.url) }
                            })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.title).lineLimit(1)
                                    Text(c.alreadyFollowed ? "Already followed" : (URL(string: c.url)?.host() ?? c.url))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .disabled(c.alreadyFollowed)
                        }
                    } header: {
                        let urls = group.items.filter { !$0.alreadyFollowed }.map(\.url)
                        Toggle(isOn: Binding(get: { !urls.isEmpty && urls.allSatisfy(picked.contains) }, set: { on in
                            if on { picked.formUnion(urls) } else { picked.subtract(urls) }
                        })) {
                            Text("\(group.name) (\(group.items.count))").font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Select All") { picked = Set(candidates.filter { !$0.alreadyFollowed }.map(\.url)) }
                Button("Select None") { picked = [] }
                Spacer()
                Text("\(picked.count) of \(candidates.count)").foregroundStyle(.secondary).monospacedDigit()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Follow \(picked.count)") { follow(candidates.filter { picked.contains($0.url) }) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 560)
    }
}

/// A site or feed address; Sift finds the feed and shows its latest items.
private struct AddFeedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var finding = false
    @State private var found: (url: String, parsed: FeedParser.Parsed)?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a Feed").font(.headline)
            TextField("Site or feed address, for example example.com", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(find)
            if finding { ProgressView().controlSize(.small) }
            if failed {
                Text("Sift found no feed there. Try the site's home page, or the feed address itself.")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let found {
                VStack(alignment: .leading, spacing: 4) {
                    Text(found.parsed.title).font(.body.weight(.semibold))
                    Text(found.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    ForEach(found.parsed.entries.prefix(3), id: \.url) { e in
                        Text("· \(e.title)").font(.callout).lineLimit(1)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if let found {
                    Button("Follow") { model.addFeed(url: found.url, parsed: found.parsed); dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Find Feed", action: find).keyboardShortcut(.defaultAction)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || finding || Demo.isOn)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func find() {
        finding = true; failed = false; found = nil
        Task {
            let result = await FeedFetcher.discover(address)
            finding = false
            if let result { found = result } else { failed = true }
        }
    }
}
