import SwiftUI

/// Today: what your feeds offer, as a short digest that ends. A row opens the
/// page next to the list and counts as seen. K (or the context menu, or Keep
/// above the page) keeps an item: it moves into "Kept from Today" and from
/// there into the library. Nothing here is saved until you keep it.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?
    @State private var showPane = false
    @FocusState private var focused: Bool

    private var picks: [TodayPick] { model.todayPicks }
    private var open: [TodayPick] { picks.filter { !model.isSeen($0.url) && !model.isKept($0.url) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if picks.isEmpty {
                ContentUnavailableView {
                    Label("Nothing new right now", systemImage: "sun.max")
                } description: {
                    Text(model.state.feeds.isEmpty
                         ? "Follow feeds in Settings > Inputs > Feeds. Today shows what they offer, twice a day."
                         : "Your feeds have nothing new from the last \(Int(TodayBuilder.windowDays)) days that you have not seen.")
                }
            } else {
                list
            }
        }
        .overlay(alignment: .trailing) {
            if showPane, let pick = picks.first(where: { $0.url == selected }) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            HStack {
                                Text(pick.reason).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                if model.isKept(pick.url) {
                                    Label("Kept", systemImage: "star.fill").foregroundStyle(.yellow)
                                } else {
                                    Button("Keep") { model.keep(pick) }
                                        .buttonStyle(.borderedProminent)
                                        .keyboardShortcut("k", modifiers: [])
                                        .help("Keep it: it moves into Kept from Today and into your library. (K)")
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.bar)
                            WebPane(tab: SafariTab(url: pick.url, title: pick.title, lastViewed: pick.date, source: TodayStore.keptSourceID)) {
                                withAnimation(.snappy) { showPane = false }
                            }
                        }
                        .frame(width: BrowserOverlay.width(for: geo.size.width))
                        .background(.background)
                        .overlay(alignment: .leading) { Divider() }
                        .shadow(color: .black.opacity(0.12), radius: 12, x: -2)
                    }
                }
            }
        }
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
                withAnimation(.snappy) { showPane = true }
            }
            .onKeyPress("k") {
                guard let url = selected, let pick = picks.first(where: { $0.url == url }) else { return .ignored }
                model.keep(pick)
                return .handled
            }
            .onKeyPress(.space) {
                guard selected != nil else { return .ignored }
                withAnimation(.snappy) { showPane.toggle() }
                return .handled
            }
            .onAppear { focused = true; _ = proxy }
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
                    Image(systemName: "dot.radiowaves.up.forward").foregroundStyle(.secondary)
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
                Text(pick.reason)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(pick.wildcard ? Color.purple : Color.orange)
            }
        }
        .padding(.vertical, 6)
        .opacity(seen && !kept ? 0.7 : 1)
    }
}
