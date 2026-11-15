import SafariServices
import SwiftUI

/// The daily deck, vertical like a short-video app: swipe up for the next
/// card, and the card you leave counts as seen. Seven unseen cards, then an
/// end page; nothing loads after it. A tap opens the link in the in-app
/// browser.
struct DeckView: View {
    @Environment(Store.self) private var store
    @State private var cards: [Item] = []
    @State private var theme: String?
    @State private var browsing: Item?
    @State private var reading: Item?
    @State private var position: String?
    @State private var connecting = false

    var body: some View {
        NavigationStack {
          GeometryReader { geo in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, item in
                        FullCard(item: item, number: i + 1, total: cards.count, mode: "deck",
                                 open: { open(item, i) }, text: { readText(item, i) })
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id(item.id)
                    }
                    if !cards.isEmpty {
                        DeckEnd(seen: cards.filter { store.isSeen($0.url) }.count, total: cards.count, deal: deal)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id("end")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollIndicators(.hidden)
            .scrollPosition(id: $position)
            .scrollClipDisabled(false)
          }
            .background(Color(.systemGroupedBackground))
            .overlay {
                if cards.isEmpty {
                    ContentUnavailableView("Nothing left here", systemImage: "checkmark.seal",
                                           description: Text("Every item in this deck has a decision. Pick another theme, or import a newer Deck folder."))
                }
            }
            .safeAreaInset(edge: .top) {
                if store.deck.demo {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                        Text("Sample data. Connect the Sift folder in iCloud Drive to see your own links.")
                            .font(.footnote)
                        Spacer(minLength: 0)
                        Button("Connect") { connecting = true }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                }
            }
            .fileImporter(isPresented: $connecting, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    store.connect(folder: url)
                    deal()
                }
            }
            .navigationTitle(theme ?? "Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All themes") { theme = nil; deal() }
                        Divider()
                        ForEach(store.deck.themes) { t in
                            Button("\(t.name) (\(t.count))") { theme = t.name; deal() }
                        }
                    } label: { Image(systemName: "circle.hexagongrid") }
                }
            }
            .sheet(item: $browsing) { InAppBrowser(url: URL(string: $0.url)!).ignoresSafeArea() }
            .sheet(item: $reading) { ReaderView(item: $0) }
            .onAppear { if cards.isEmpty { deal() } }
        }
    }

    private func open(_ item: Item, _ i: Int) {
        guard URL(string: item.url) != nil else { return }
        store.record(item, .open, mode: "deck", position: i)
        store.setSeen([item], true, mode: "deck")
        browsing = item
    }

    private func readText(_ item: Item, _ i: Int) {
        store.record(item, .read, mode: "deck", position: i)
        reading = item
    }

    private func deal() {
        cards = store.deal(theme: theme)
        position = cards.first?.id
    }
}

/// One full-height card. A card on screen for a second counts as seen when
/// you swipe on, like a mail you opened. The rail has the saved text and a
/// switch back to unseen.
struct FullCard: View {
    @Environment(Store.self) private var store
    let item: Item
    let number: Int
    let total: Int
    let mode: String
    let open: () -> Void
    let text: () -> Void
    @State private var shownAt: Date?

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                Text("\(number)/\(total)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear { shownAt = Date() }
        .onDisappear {
            if let shownAt, Date().timeIntervalSince(shownAt) > 1 { store.setSeen([item], true, mode: mode) }
            shownAt = nil
        }
    }

    /// A vertical video (Short, reel, TikTok) plays inline after a tap; its
    /// Text pill opens the reader. Other items open in the browser on a tap.
    @ViewBuilder private var content: some View {
        if let video = VerticalVideo.detect(item) {
            VerticalVideoCard(item: item, video: video, text: text) {
                ActionRail(item: item, text: text, mode: mode, showText: false)
            }
        } else {
            CardView(item: item, tall: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                // Text and seen sit on the card, bottom right.
                .overlay(alignment: .bottomTrailing) {
                    ActionRail(item: item, text: text, mode: mode).padding(12)
                }
        }
    }
}

/// The saved text, and seen or unseen, as two small buttons on the card.
struct ActionRail: View {
    @Environment(Store.self) private var store
    let item: Item
    let text: () -> Void
    let mode: String
    /// False when the card has its own Text pill (vertical video).
    var showText = true

    var body: some View {
        let seen = store.isSeen(item.url)
        let hasText = showText && !(item.text.isEmpty && item.transcript.isEmpty && item.passage.isEmpty)
        HStack(spacing: 8) {
            if hasText {
                Button(action: text) {
                    Label(item.transcript.isEmpty ? "Text" : "Words",
                          systemImage: item.transcript.isEmpty ? "doc.plaintext" : "captions.bubble")
                }
            }
            Button { store.setSeen([item], !seen, mode: mode) } label: {
                Label(seen ? "Seen" : "Unseen", systemImage: seen ? "eye" : "circle.fill")
                    .foregroundStyle(seen ? Color.primary : Color.accentColor)
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.plain)
        .labelStyle(PillLabel())
    }
}

private struct PillLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon; configuration.title }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }
}

/// The last page: what you did, and no automatic next.
private struct DeckEnd: View {
    let seen: Int
    let total: Int
    let deal: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(.green)
            Text("That's today's deck").font(.title2.weight(.semibold))
            Text("\(seen) of \(total) seen").font(.title3).foregroundStyle(.secondary)
            Text("Seen links show as seen on your Mac too. Anything you marked unseen comes back in a later deck.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer().frame(height: 20)
            // Deliberately quiet: another deck is a choice, not the default.
            Button("Deal another deck", action: deal)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Safari inside the app (SFSafariViewController): the page, with Safari's
/// own Done button, reader and share.
struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
