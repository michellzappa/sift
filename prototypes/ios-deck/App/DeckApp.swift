import SwiftUI
import UniformTypeIdentifiers

/// Sift deck prototype. Throwaway: it answers how swipe-as-decision and a
/// deep stream feel with real content. It reads a deck.json exported on the
/// Mac and writes only its own decision log. See README.md.
@main
struct DeckApp: App {
    @State private var store = Store()
    @State private var tab = "scan"
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            // Today: what your feeds offer, a digest that ends. Library: what
            // you saved, unseen first, as a deck or deeper by theme.
            TabView(selection: $tab) {
                // Scan, Watch, Read first, each with Today (offered) and
                // Library (saved) at the top (owner, 2026-11-16). The swipe
                // deck, Feeds and Log sit in the Themes tab's menu.
                ForEach(ReadingMode.allCases) { mode in
                    ModeTab(mode: mode)
                        .tabItem { Label(mode.title, systemImage: mode.symbol) }.tag(mode.rawValue)
                }
                ThemesView().tabItem { Label("Themes", systemImage: "circle.hexagongrid") }.tag("themes")
            }
            .environment(store)
            // Seen marks from the Mac, and a newer Deck, whenever the app comes back.
            .onChange(of: phase) { _, p in if p == .active { store.sync() } }
        }
    }
}

/// Library: your saved items as cards, seven unseen ones that end.
struct LibraryView: View {
    // One level: cards (owner, 2026-11-15). The deep stream (StreamView)
    // stays in the code for later, not in the app.
    var body: some View { DeckView() }
}

/// What you did, the week's numbers, and the deck file.
struct LogView: View {
    @Environment(Store.self) private var store
    @State private var importing = false
    @State private var connecting = false
    @AppStorage("watch.autoplay") private var autoplay = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { CreatorGraphView() } label: { Label("Your Graph", systemImage: "person.2") }
                    NavigationLink { FeedsView() } label: { Label("Feeds", systemImage: "dot.radiowaves.up.forward") }
                    NavigationLink { AlgorithmView() } label: { Label("How Today Works", systemImage: "function") }
                    NavigationLink { YouView() } label: { Label("What Sift Knows About You", systemImage: "person.text.rectangle") }
                } footer: {
                    Text("How Today Works shows the formula, what each action teaches Sift, and today's picks with their scores.")
                }
                Section("This week") {
                    let since = store.weekStart
                    LabeledContent("Read", value: "\(store.count(.read, since: since))")
                    LabeledContent("Kept", value: "\(store.count(.keep, since: since))")
                    LabeledContent("Sent", value: "\(store.count(.send, since: since))")
                    LabeledContent("Let go", value: "\(store.count(.letGo, since: since))")
                    LabeledContent("Later", value: "\(store.count(.later, since: since))")
                    LabeledContent("Threads opened", value: "\(Set(store.log.compactMap(\.thread)).count)")
                }
                Section {
                    Toggle("Autoplay videos, muted", isOn: $autoplay)
                } header: {
                    Text("Watch")
                } footer: {
                    Text("A YouTube video in Today's Watch tab plays without sound while its card is on screen. Tap it for sound. TikTok and Instagram wait for a tap.")
                }
                Section {
                    LabeledContent("Folder", value: store.connectedFolder ?? "Not connected")
                    Button(store.connectedFolder == nil ? "Connect iCloud Drive/Sift…" : "Connect Again…") { connecting = true }
                    Button("Sync Now") { store.sync() }.disabled(store.connectedFolder == nil)
                } header: {
                    Text("Sync with the Mac")
                } footer: {
                    Text("Pick the Sift folder in iCloud Drive once. The phone then reads the newest Deck and the seen marks from your Macs, and writes its own, every time it opens.")
                }
                Section {
                    LabeledContent("Items", value: "\(store.deck.items.count) in \(store.deck.themes.count) themes")
                    LabeledContent("Synthesis cards", value: "\(store.deck.synthesis.count)")
                    Button("Import Deck folder…") { importing = true }
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
                } header: {
                    Text(store.deck.demo ? "Deck: sample data" : "Deck: your library")
                } footer: {
                    Text("On the Mac, run prototypes/ios-deck/export-deck.py. It writes a Deck folder (deck.json and images) to iCloud Drive/Sift. Pick the Deck folder here.")
                }
                Section {
                    ShareLink(item: Store.logURL) { Label("Share log.jsonl", systemImage: "square.and.arrow.up") }
                        .disabled(store.log.isEmpty)
                    Button("Clear log", role: .destructive) { store.clearLog() }
                } footer: {
                    Text("Every swipe and tap is a line in log.jsonl. Nothing goes to Sift or anywhere else.")
                }
                Section("Last decisions") {
                    let map = store.byID
                    ForEach(Array(store.log.suffix(30).reversed().enumerated()), id: \.offset) { _, e in
                        HStack {
                            Image(systemName: e.decision.symbol).foregroundStyle(e.decision.color).frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(map[e.item]?.title ?? e.item).lineLimit(1)
                                Text("\(e.mode) · \(e.theme) · \(e.position)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .json]) { result in
                if case .success(let url) = result { store.importDeck(from: url) }
            }
            .fileImporter(isPresented: $connecting, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { store.connect(folder: url) }
            }
        }
    }
}
