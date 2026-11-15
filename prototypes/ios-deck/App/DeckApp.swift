import SwiftUI
import UniformTypeIdentifiers

/// Sift deck prototype. Throwaway: it answers how swipe-as-decision and a
/// deep stream feel with real content. It reads a deck.json exported on the
/// Mac and writes only its own decision log. See README.md.
@main
struct DeckApp: App {
    @State private var store = Store()
    @State private var tab = "today"
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            // Today: what your feeds offer, a digest that ends. Library: what
            // you saved, unseen first, as a deck or deeper by theme.
            TabView(selection: $tab) {
                TodayView(goToLibrary: { tab = "library" })
                    .tabItem { Label("Today", systemImage: "sun.max") }.tag("today")
                LibraryView()
                    .tabItem { Label("Library", systemImage: "books.vertical") }.tag("library")
                ListsView().tabItem { Label("Lists", systemImage: "tray.full") }.tag("lists")
                LogView().tabItem { Label("Log", systemImage: "list.bullet.rectangle") }.tag("log")
            }
            .environment(store)
            // Seen marks from the Mac, and a newer Deck, whenever the app comes back.
            .onChange(of: phase) { _, p in if p == .active { store.sync() } }
        }
    }
}

/// Library: your saved items. Deck is seven unseen cards that end; Deeper
/// goes down one theme at a time.
struct LibraryView: View {
    @State private var mode = "deck"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                Text("Deck").tag("deck")
                Text("Deeper").tag("deeper")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            if mode == "deck" { DeckView() } else { StreamView() }
        }
    }
}

/// What you did, the week's numbers, and the deck file.
struct LogView: View {
    @Environment(Store.self) private var store
    @State private var importing = false
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("Log")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .json]) { result in
                if case .success(let url) = result { store.importDeck(from: url) }
            }
            .fileImporter(isPresented: $connecting, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { store.connect(folder: url) }
            }
        }
    }
}
