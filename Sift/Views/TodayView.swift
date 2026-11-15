import SwiftUI

/// Today: what your feeds offer, as a short digest that ends. A row opens the
/// page next to the list and counts as seen. S (or the context menu, or Keep
/// above the page) keeps an item: it moves into "Kept from Today" and from
/// there into the library. Nothing here is saved until you keep it.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    private var picks: [TodayPick] { model.todayPicks }
    private var open: [TodayPick] { picks.filter { !model.isSeen($0.url) && !model.isKept($0.url) } }

    var body: some View {
        OfferedList(picks: picks, header: header, empty: ContentUnavailableView {
            Label("Nothing new right now", systemImage: "sun.max")
        } description: {
            Text(model.state.feeds.isEmpty
                 ? "Follow feeds with Add Feed in the toolbar. Today shows what they offer, twice a day."
                 : "Your feeds have nothing new from the last \(Int(TodayBuilder.windowDays)) days that you have not seen.")
        })
        .navigationTitle("Today")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button { model.refreshToday(force: true) } label: { Label("New Digest", systemImage: "arrow.triangle.2.circlepath") }
                    .help("Build Today again now from what your feeds offer.")
            }
        }
        .onAppear { model.refreshToday() }
    }

    private var subtitle: String {
        guard let digest = model.state.today else { return "" }
        let slot = digest.slot.formatted(date: .omitted, time: .shortened)
        return "\(picks.count - open.count) of \(picks.count) done · digest of \(slot)"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max").foregroundStyle(.orange)
            Text(open.isEmpty && !picks.isEmpty
                 ? "That's Today. The next digest comes at \(TodayBuilder.nextSlot().formatted(date: .omitted, time: .shortened))."
                 : "\(open.count) new from your feeds. Keep what you want in your library; the rest leaves Today on its own.")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// One feed or one folder, like a reader: its recent items, newest first.
/// No unread counts: opening counts as seen, Keep saves.
struct FeedItemsView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let feeds: [Feed]

    var body: some View {
        let picks = model.items(of: feeds)
        OfferedList(picks: picks, header: HStack {
            Text(feeds.count == 1 ? (feeds[0].site ?? feeds[0].url) : "\(feeds.count) feeds")
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }.padding(.horizontal, 14).padding(.vertical, 8),
        empty: ContentUnavailableView("Nothing here yet", systemImage: "dot.radiowaves.up.forward",
                                      description: Text(feeds.first?.lastError ?? "Sift checks feeds about once an hour.")))
        .navigationTitle(title)
        .navigationSubtitle("\(picks.count) items")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.fetchFeeds(force: true) } } label: { Label("Check Now", systemImage: "arrow.clockwise") }
                    .disabled(model.isFetchingFeeds)
            }
        }
    }
}

/// A list of offered items with the page beside it. Shared by Today and the
/// feed and folder lists.
struct OfferedList<Header: View, Empty: View>: View {
    @Environment(AppModel.self) private var model
    let picks: [TodayPick]
    let header: Header
    let empty: Empty
    @State private var selected: String?
    @State private var showPane = false
    @State private var showPage = false
    @State private var keyOwner = UUID()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if picks.isEmpty {
                empty
            } else {
                list
            }
        }
        // The reader sits beside the list; the list gets narrower, nothing
        // covers it.
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if showPane, let pick = picks.first(where: { $0.url == selected }) {
                        VStack(spacing: 0) {
                            HStack {
                                Text(pick.reason.isEmpty ? pick.feedTitle : pick.reason).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                // The reader first; the website on request.
                                Picker("", selection: $showPage) {
                                    Text("Reader").tag(false)
                                    Text("Page").tag(true)
                                }
                                .pickerStyle(.segmented).labelsHidden().fixedSize()
                                Button { withAnimation(.snappy) { showPane = false } } label: { Image(systemName: "sidebar.right") }
                                    .buttonStyle(.borderless)
                                    .help("Close the reader (Space)")
                                if model.isKept(pick.url) {
                                    Label("Kept", systemImage: "star.fill").foregroundStyle(.yellow)
                                } else {
                                    Button("Keep") { model.keep(pick) }
                                        .buttonStyle(.borderedProminent)
                                        .help("Keep it: it moves into Kept from Today and into your library. (S)")
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.bar)
                            if !showPage {
                                // The reader first, like Reeder: the feed's text, else the
                                // article fetched once; the website on the Page switch.
                                FeedReader(pick: pick)
                                    .id(pick.url)
                                    .onAppear { model.setSeen([pick.url], true) }
                            } else {
                                WebPane(tab: SafariTab(url: pick.url, title: pick.title, lastViewed: pick.date, source: TodayStore.keptSourceID)) {
                                    withAnimation(.snappy) { showPane = false }
                                }
                            }
                        }
                        .containerRelativeFrame(.horizontal) { width, _ in BrowserOverlay.width(for: width) }
                        .background(.background)
                        .overlay(alignment: .leading) { Divider() }
                        .transition(.move(edge: .trailing))
            }
        }
    }

    /// Google Reader keys for offered items (KeyMap.swift); s keeps.
    private func handleKey(_ action: KeyAction, _ proxy: ScrollViewProxy) -> Bool {
        let pick = picks.first { $0.url == selected }
        func move(_ by: Int) {
            guard !picks.isEmpty else { return }
            let i = picks.firstIndex { $0.url == selected }.map { min(max($0 + by, 0), picks.count - 1) } ?? 0
            selected = picks[i].url
            proxy.scrollTo(picks[i].url)
        }
        switch action {
        case .next: move(1)
        case .previous: move(-1)
        case .open:
            if selected == nil { move(1) }
            withAnimation(.snappy) { showPane.toggle() }
        case .original:
            guard let pick else { return false }
            model.openInApp(pick.url)
        case .keep:
            guard let pick else { return false }
            if model.isKept(pick.url) { model.unkeep(pick.url) } else { model.keep(pick) }
        case .toggleSeen:
            guard let pick else { return false }
            model.setSeen([pick.url], !model.isSeen(pick.url))
        case .markAllSeen:
            model.setSeen(picks.map(\.url), true)
            model.note("Marked \(picks.count) as seen")
        case .copyLink:
            guard let pick else { return false }
            model.copy(pick.url)
            model.note("Link copied")
        case .follow:
            guard let pick, let input = AppModel.followInput(forLink: pick.url) else { return false }
            model.followQuick(input)
        default:
            return false
        }
        return true
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                ForEach(picks) { pick in
                    TodayRow(pick: pick)
                        .tag(pick.url)
                        .id(pick.url)
                        .contextMenu {
                            if model.isKept(pick.url) {
                                Button("Remove from Kept") { model.unkeep(pick.url) }
                            } else {
                                Button("Keep") { model.keep(pick) }
                            }
                            Button(model.isSeen(pick.url) ? "Mark as Unseen" : "Mark as Seen") {
                                model.setSeen([pick.url], !model.isSeen(pick.url))
                            }
                            Divider()
                            Button("Open in Safari") { TabActions.openInSafari(pick.url) }
                            Button("Copy Link") { model.copy(pick.url) }
                        }
                }
            }
            .listStyle(.inset)
            .focused($focused)
            .onChange(of: selected) { _, new in
                guard new != nil else { return }
                showPage = false
                withAnimation(.snappy) { showPane = true }
            }
            .onKeyPress(.space) {
                guard selected != nil else { return .ignored }
                withAnimation(.snappy) { showPane.toggle() }
                return .handled
            }
            .onAppear {
                focused = true
                KeyRouter.shared.register(keyOwner) { handleKey($0, proxy) }
            }
            .onDisappear { KeyRouter.shared.unregister(keyOwner) }
        }
    }
}

/// One offered item: picture, title (bold while unseen), feed and time, two
/// lines of summary, and why it is here.
private struct TodayRow: View {
    @Environment(AppModel.self) private var model
    let pick: TodayPick

    var body: some View {
        let seen = model.isSeen(pick.url)
        let kept = model.isKept(pick.url)
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                if let s = pick.image, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                    }
                } else {
                    // No picture: the site's icon, in grey.
                    FeedIconView(feedID: pick.feedID, size: 18).id(model.feedIconVersion)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if kept {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    } else if !seen {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                    }
                    Text(pick.title)
                        .font(.body.weight(seen || kept ? .regular : .semibold))
                        .foregroundStyle(seen && !kept ? .secondary : .primary)
                        .lineLimit(2)
                }
                Text([pick.feedTitle, pick.date?.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !pick.summary.isEmpty {
                    Text(pick.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if !pick.reason.isEmpty {
                    Text(pick.reason)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(pick.wildcard ? Color.purple : Color.orange)
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(seen && !kept ? 0.7 : 1)
    }
}

/// The feed's own text for an offered item, as Markdown: title, source,
/// then each block (headings, quotes, lists, code, paragraphs). Links open
/// in the browser.
struct FeedReader: View {
    @Environment(AppModel.self) private var model
    let pick: TodayPick
    @State private var content: String?
    @State private var loading = false

    init(pick: TodayPick) {
        self.pick = pick
        _content = State(initialValue: pick.content)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(pick.title).font(.title2.weight(.semibold))
                Text([pick.feedTitle, pick.date?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if content == nil {
                    if !pick.summary.isEmpty { Text(pick.summary).font(.body).lineSpacing(3) }
                    if loading {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Getting the full article…").foregroundStyle(.secondary) }
                    } else if pick.summary.isEmpty || pick.summary.hasSuffix("…") {
                        // Only when the text is visibly cut: a short post is complete.
                        Text("This feed sends only a summary, and Sift could not read the full article. Page shows the website.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    if block.hasPrefix("```") {
                        Text(block.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .newlines))
                            .font(.system(.callout, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                    } else if block.hasPrefix("- ") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(block.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundStyle(.secondary)
                                    ReaderBlock(block: String(line.drop { $0 == "-" || $0 == " " }))
                                }
                            }
                        }
                    } else {
                        // A quote: every line starts with "> "; ReaderBlock wants one.
                        ReaderBlock(block: block.hasPrefix("> ")
                            ? "> " + block.split(separator: "\n").map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : String($0) }.joined(separator: "\n")
                            : block)
                    }
                }
            }
            .textSelection(.enabled)
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // Links in the text open in Sift's browser, not Safari.
        .environment(\.openURL, OpenURLAction { url in model.openInApp(url.absoluteString); return .handled })
        .task {
            guard content == nil else { return }
            loading = true
            content = await model.fullText(for: pick)
            loading = false
        }
    }

    /// Blocks split on blank lines, keeping ``` code blocks whole.
    private var blocks: [String] {
        guard let content else { return [] }
        var out: [String] = []
        var code: String?
        for part in content.components(separatedBy: "\n\n") {
            if var c = code {
                c += "\n\n" + part
                if part.hasSuffix("```") { out.append(c); code = nil } else { code = c }
            } else if part.hasPrefix("```"), !(part.count > 3 && part.hasSuffix("```")) {
                code = part
            } else {
                out.append(part)
            }
        }
        if let c = code { out.append(c) }
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
