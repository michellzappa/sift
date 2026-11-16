import SwiftUI

/// Today: what your feeds offer, as a short digest that ends. A row opens the
/// page next to the list and counts as seen. S (or the context menu, or Keep
/// above the page) keeps an item: it moves into "Kept from Today" and from
/// there into the library. Nothing here is saved until you keep it.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    private var picks: [TodayPick] { model.todayPicks }
    private var open: [TodayPick] { model.inMode(picks).filter { !model.isSeen($0.url) && !model.isKept($0.url) } }

    var body: some View {
        OfferedList(picks: picks, header: EmptyView(), empty: ContentUnavailableView {
            Label("Nothing new right now", systemImage: "sun.max")
        } description: {
            Text(model.state.feeds.isEmpty
                 ? "Follow feeds with Add Feed in the toolbar. Today shows the best of what they offer and updates as they post."
                 : "Your feeds have nothing new from the last \(Int(TodayBuilder.windowDays)) days that you have not seen.")
        })
        .navigationTitle("Today")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) { ModePicker() }
            ToolbarItem {
                Button { model.refreshToday(force: true) } label: { Label("Rebuild Today", systemImage: "arrow.triangle.2.circlepath") }
                    .help("Build Today again from nothing. It also updates by itself when feeds bring new items.")
            }
            ToolbarItem {
                Button { model.showHowToday = true } label: { Label("How Today Works", systemImage: "questionmark.circle") }
                    .help("How Today picks and orders items, and what it learned about each feed")
            }
        }
        .onAppear { model.refreshToday() }
    }

    /// The count lives in the subtitle, as in Mail; no banner over the list.
    private var subtitle: String {
        guard model.state.today != nil, !picks.isEmpty else { return "" }
        return open.isEmpty ? "All seen" : "\(open.count) new"
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
            if feeds.count == 1 {
                FeedStandingBar(feed: feeds[0])
            } else {
                Text("\(feeds.count) feeds").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.vertical, 8),
        empty: ContentUnavailableView("Nothing here yet", systemImage: "dot.radiowaves.up.forward",
                                      description: Text(feeds.first?.lastError ?? "Sift checks feeds about once an hour.")))
        .navigationTitle(title)
        .navigationSubtitle("\(model.inMode(picks).count) items")
        .toolbar {
            ToolbarItem(placement: .principal) { ModePicker() }
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
    /// The picks in the current mode (Scan, Watch, Read or All).
    private var shown: [TodayPick] { model.inMode(picks) }
    @State private var gridOwner = UUID()
    @State private var past = ScrollPast()
    let header: Header
    let empty: Empty
    @State private var selected: String?
    @State private var showPane = false
    @State private var showPage = false
    @State private var keyOwner = UUID()
    @FocusState private var focused: Bool

    var body: some View {
        // A split view, as in Mail and NetNewsWire: the list, a divider you
        // can drag, the reader on the content background.
        ReaderSplit(showing: showPane && shown.contains { $0.url == selected }) {
        VStack(spacing: 0) {
            if Header.self != EmptyView.self {
                header
                Divider()
            }
            if shown.isEmpty {
                if let mode = model.listMode, !picks.isEmpty {
                    ContentUnavailableView(mode.empty, systemImage: mode.symbol,
                                           description: Text("Switch to All, or to another mode, in the toolbar (0 to 3)."))
                } else {
                    empty
                }
            } else if model.listMode == .watch {
                grid
            } else {
                list
            }
        }
        } pane: {
            if showPane, let pick = shown.first(where: { $0.url == selected }) {
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
                                    .onAppear { model.setSeen([pick.url], true); model.signal(pick, "open") }
                            } else {
                                WebPane(tab: SafariTab(url: pick.url, title: pick.title, lastViewed: pick.date, source: TodayStore.keptSourceID)) {
                                    withAnimation(.snappy) { showPane = false }
                                }
                            }
                        }
            }
        }
    }

    /// Google Reader keys for offered items (KeyMap.swift); s keeps.
    private func handleKey(_ action: KeyAction, _ proxy: ScrollViewProxy) -> Bool {
        let pick = shown.first { $0.url == selected }
        func move(_ by: Int) {
            guard !shown.isEmpty else { return }
            let i = shown.firstIndex { $0.url == selected }.map { min(max($0 + by, 0), shown.count - 1) } ?? 0
            selected = shown[i].url
            proxy.scrollTo(shown[i].url)
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
            model.setSeen(shown.map(\.url), true)
            model.note("Marked \(shown.count) as seen")
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

    @ViewBuilder
    private func menu(_ pick: TodayPick) -> some View {
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

    /// Watch: videos as cards, tall ones at their own shape.
    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [WatchCard.column], alignment: .leading, spacing: 22) {
                    ForEach(shown) { pick in
                        WatchCard(title: pick.title,
                                  byline: [pick.feedTitle, pick.date?.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "),
                                  image: pick.image,
                                  vertical: pick.vertical == true || Modes.isVertical(pick.url),
                                  seconds: nil,
                                  seen: model.isSeen(pick.url),
                                  selected: selected == pick.url,
                                  kept: model.isKept(pick.url))
                            .id(pick.url)
                            .onTapGesture { selected = pick.url }
                            .contextMenu { menu(pick) }
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .focusable()
            .focusEffectDisabled()
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
                KeyRouter.shared.register(gridOwner) { handleKey($0, proxy) }
            }
            .onDisappear { KeyRouter.shared.unregister(gridOwner) }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, pick in
                    TodayRow(pick: pick, mode: model.listMode)
                        .tag(pick.url)
                        .id(pick.url)
                        .contextMenu { menu(pick) }
                        // Scan: a headline scrolled past counts as seen.
                        .onAppear { if model.listMode == .scan { past.appear(pick.url, at: i) } }
                        .onDisappear {
                            guard model.listMode == .scan else { return }
                            past.disappear(pick.url, at: i) { model.setSeen([$0], true) }
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
                past.active = true
                KeyRouter.shared.register(keyOwner) { handleKey($0, proxy) }
            }
            .onDisappear { past.active = false; KeyRouter.shared.unregister(keyOwner) }
        }
    }
}

/// One offered item: picture, title (bold while unseen), feed and time, two
/// lines of summary, and why it is here.
private struct TodayRow: View {
    @Environment(AppModel.self) private var model
    let pick: TodayPick
    /// Scan: no picture and no summary. Read: reading time and three lines.
    var mode: ReadingMode? = nil

    /// The summary, or the article's first line when the feed's summary says
    /// nothing ("…", empty).
    private var lede: String? {
        let summary = pick.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.count >= 12 { return summary }
        guard let content = pick.content else { return summary }
        let first = content.components(separatedBy: "\n\n").first { !$0.hasPrefix("#") && $0.count > 20 } ?? ""
        return first.replacingOccurrences(of: #"[*_`>\[\]]|\(https?://[^)]+\)"#, with: "", options: .regularExpression)
    }

    /// "8 min read" in Read, from the text Sift has.
    private var readingTime: String? {
        guard mode == .read else { return nil }
        let words = Modes.words(pick.content)
        return words > 0 ? "\(Modes.minutes(words)) min read" : nil
    }

    var body: some View {
        let seen = model.isSeen(pick.url)
        let kept = model.isKept(pick.url)
        HStack(alignment: .top, spacing: 12) {
            if mode != .scan {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                if let s = pick.image, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                    }
                } else {
                    // No picture: the site's icon.
                    FeedIconView(feedID: pick.feedID, size: 18, grey: seen && !kept).id(model.feedIconVersion)
                }
            }
            // Unseen in colour, seen in grey, like read mail.
            .saturation(seen && !kept ? 0 : 1)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 3) {
                // The unseen dot (or the kept star) sits after the title.
                HStack(alignment: .top, spacing: 6) {
                    Text(pick.title)
                        .font(.body.weight(seen || kept ? .regular : .semibold))
                        .foregroundStyle(seen && !kept ? .secondary : .primary)
                        .lineLimit(2)
                    if kept {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption).padding(.top, 2)
                    } else if !seen {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7).padding(.top, 6)
                    }
                }
                Text([pick.feedTitle, pick.date?.formatted(.relative(presentation: .named)), readingTime].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if mode != .scan, let line = lede, !line.isEmpty {
                    Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(mode == .read ? 3 : 2)
                }
                if !pick.reason.isEmpty {
                    Label {
                        Text(pick.reason)
                    } icon: {
                        if pick.hot == true { Image(systemName: "flame.fill") }
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(pick.wildcard ? Color.purple : (pick.hot == true ? Color.red : Color.orange))
                }
            }
        }
        .padding(.vertical, mode == .scan ? 2 : 6)
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
                            ? "> " + block.split(separator: "\n").map { line in
                                line.hasPrefix(">") ? String(line.dropFirst().drop { $0 == " " }) : String(line)
                            }.joined(separator: "\n")
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
        out = out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // Text saved before 1.4.2 can have a lone ">" before the quoted
        // paragraph: it quotes the next block.
        var merged: [String] = []
        var quoteNext = false
        for block in out {
            if block == ">" { quoteNext = true; continue }
            merged.append(quoteNext && !block.hasPrefix(">") ? "> " + block : block)
            quoteNext = false
        }
        return merged
    }
}
