import SafariServices
import SwiftUI

/// The daily deck, vertical like a short-video app: swipe up for the next
/// card. Seven cards, then an end page; nothing loads after it. Decisions
/// are the buttons on the right edge. A tap opens the link in the in-app
/// browser.
struct DeckView: View {
    @Environment(Store.self) private var store
    @State private var cards: [Item] = []
    @State private var decided: [String: Decision] = [:]
    @State private var theme: String?
    @State private var browsing: Item?
    @State private var reading: Item?
    @State private var position: String?
    @State private var feedback = 0

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { i, item in
                        FullCard(item: item, number: i + 1, total: cards.count, decision: decided[item.id],
                                 open: { open(item, i) }, text: { readText(item, i) }) { d in
                            decide(item, d, i)
                        }
                        .containerRelativeFrame(.vertical)
                        .id(item.id)
                    }
                    if !cards.isEmpty {
                        DeckEnd(decided: decided, total: cards.count, deal: deal)
                            .containerRelativeFrame(.vertical)
                            .id("end")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $position)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if cards.isEmpty {
                    ContentUnavailableView("Nothing left here", systemImage: "checkmark.seal",
                                           description: Text("Every item in this deck has a decision. Pick another theme, or import a newer Deck folder."))
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
            .sensoryFeedback(.impact(weight: .medium), trigger: feedback)
            .onAppear { if cards.isEmpty { deal() } }
        }
    }

    private func open(_ item: Item, _ i: Int) {
        guard URL(string: item.url) != nil else { return }
        store.record(item, .open, mode: "deck", position: i)
        browsing = item
    }

    private func readText(_ item: Item, _ i: Int) {
        store.record(item, .read, mode: "deck", position: i)
        reading = item
    }

    private func decide(_ item: Item, _ d: Decision, _ i: Int) {
        decided[item.id] = d
        feedback += 1
        store.record(item, d, mode: "deck", position: i)
        // A decision moves on to the next card, like a swipe up.
        let next = i + 1 < cards.count ? cards[i + 1].id : "end"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.snappy) { position = next }
        }
    }

    private func deal() {
        cards = store.deal(theme: theme)
        decided = [:]
        position = cards.first?.id
    }
}

/// One full-height card with the action rail on the right.
struct FullCard: View {
    @Environment(Store.self) private var store
    let item: Item
    let number: Int
    let total: Int
    let decision: Decision?
    let open: () -> Void
    let text: () -> Void
    let decide: (Decision) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            CardView(item: item, tall: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                .overlay(alignment: .topTrailing) {
                    Text("\(number)/\(total)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            ActionRail(item: item, decision: decision, text: text, decide: decide)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Keep, send, let go, and the saved text. The chosen one stays lit.
struct ActionRail: View {
    let item: Item
    let decision: Decision?
    let text: () -> Void
    let decide: (Decision) -> Void

    var body: some View {
        VStack(spacing: 18) {
            railButton(.keep)
            railButton(.send)
            railButton(.letGo)
            Button(action: text) {
                VStack(spacing: 3) {
                    Image(systemName: item.transcript.isEmpty ? "doc.plaintext" : "captions.bubble")
                        .font(.title3)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                    Text(item.transcript.isEmpty ? "Text" : "Words").font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .disabled(item.text.isEmpty && item.transcript.isEmpty && item.passage.isEmpty)
        }
        .padding(.bottom, 24)
    }

    private func railButton(_ d: Decision) -> some View {
        Button { decide(d) } label: {
            VStack(spacing: 3) {
                Image(systemName: d.symbol)
                    .font(.title3.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(decision == d ? d.color : Color(.tertiarySystemFill)))
                    .foregroundStyle(decision == d ? .white : .primary)
                Text(d.label).font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The last page: what you did, and no automatic next.
private struct DeckEnd: View {
    let decided: [String: Decision]
    let total: Int
    let deal: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(.green)
            Text("That's today's deck").font(.title2.weight(.semibold))
            HStack(spacing: 18) {
                ForEach([Decision.keep, .send, .letGo], id: \.self) { d in
                    VStack {
                        Text("\(decided.values.filter { $0 == d }.count)").font(.title.weight(.bold)).foregroundStyle(d.color)
                        Text(d.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("\(total - decided.count) passed without a decision. They come back in a later deck.")
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
