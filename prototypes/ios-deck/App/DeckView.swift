import SwiftUI

/// The daily deck: seven cards, one decision each, then it ends.
/// Right keep, left let go, up send, down later (two per deck). Tap reads.
struct DeckView: View {
    @Environment(Store.self) private var store
    @State private var cards: [Item] = []
    @State private var index = 0
    @State private var results: [Decision] = []
    @State private var laterLeft = 2
    @State private var theme: String?
    @State private var reading: Item?
    @State private var offset: CGSize = .zero
    @State private var feedback = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                progress
                ZStack {
                    if index < cards.count {
                        // The next card peeks under the current one.
                        if index + 1 < cards.count {
                            CardView(item: cards[index + 1])
                                .scaleEffect(0.95).offset(y: 12).opacity(0.6)
                        }
                        CardView(item: cards[index])
                            .overlay(alignment: .top) { intentBadge }
                            .offset(offset)
                            .rotationEffect(.degrees(Double(offset.width / 22)))
                            .gesture(drag)
                            .onTapGesture { reading = cards[index]; store.record(cards[index], .read, mode: "deck", position: index) }
                            .id(cards[index].id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                    } else if !cards.isEmpty {
                        EndCard(results: results, deal: deal)
                    } else {
                        ContentUnavailableView("Nothing left here", systemImage: "checkmark.seal",
                                               description: Text("Every item in this deck has a decision. Pick another theme, or import a newer deck.json."))
                    }
                }
                .padding(.horizontal, 16)
                legend
            }
            .padding(.bottom, 8)
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
            .sheet(item: $reading) { ReaderView(item: $0) }
            .sensoryFeedback(.impact(weight: .medium), trigger: feedback)
            .onAppear { if cards.isEmpty { deal() } }
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(cards.count, 1), id: \.self) { i in
                Capsule()
                    .fill(i < results.count ? results[i].color : (i == index ? Color.primary.opacity(0.5) : Color.primary.opacity(0.12)))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var legend: some View {
        HStack {
            Label("Let go", systemImage: "arrow.left")
            Spacer()
            Label("Send ↑ · Later ↓ (\(laterLeft))", systemImage: "arrow.up.arrow.down")
            Spacer()
            Label("Keep", systemImage: "arrow.right").labelStyle(TrailingIcon())
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
    }

    private var intent: Decision? {
        let x = offset.width, y = offset.height
        if abs(x) > abs(y) {
            if x > 60 { return .keep }
            if x < -60 { return .letGo }
        } else {
            if y < -60 { return .send }
            if y > 60, laterLeft > 0 { return .later }
        }
        return nil
    }

    @ViewBuilder private var intentBadge: some View {
        if let intent {
            Label(intent.label, systemImage: intent.symbol)
                .font(.headline)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(intent.color.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
                .padding(.top, 18)
        }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                let x = value.translation.width, y = value.translation.height
                var decision: Decision?
                if abs(x) > abs(y) {
                    if x > 120 { decision = .keep } else if x < -120 { decision = .letGo }
                } else {
                    if y < -120 { decision = .send } else if y > 120, laterLeft > 0 { decision = .later }
                }
                guard let decision else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero }
                    return
                }
                decide(decision, fling: value.translation)
            }
    }

    private func decide(_ d: Decision, fling: CGSize) {
        let item = cards[index]
        store.record(item, d, mode: "deck", position: index)
        if d == .later { laterLeft -= 1 }
        feedback += 1
        withAnimation(.easeIn(duration: 0.2)) {
            offset = CGSize(width: fling.width * 4, height: fling.height * 4)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            results.append(d)
            offset = .zero
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { index += 1 }
        }
    }

    private func deal() {
        cards = store.deal(theme: theme)
        index = 0
        results = []
        laterLeft = 2
        offset = .zero
    }
}

/// The end of the deck: what you did, and no automatic next.
private struct EndCard: View {
    let results: [Decision]
    let deal: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(.green)
            Text("That's today's deck").font(.title2.weight(.semibold))
            HStack(spacing: 18) {
                ForEach([Decision.keep, .send, .letGo, .later], id: \.self) { d in
                    VStack {
                        Text("\(results.filter { $0 == d }.count)").font(.title.weight(.bold)).foregroundStyle(d.color)
                        Text(d.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Your library is \(results.filter { $0 != .later }.count) links lighter.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer().frame(height: 20)
            // Deliberately quiet: another deck is a choice, not the default.
            Button("Deal another deck", action: deal)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon }
    }
}
