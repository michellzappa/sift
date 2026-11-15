import SwiftUI

// Feeds shared with the Mac. The Mac writes iCloud Drive/Sift/Deck/feeds.json
// (its followed feeds and the outcome of each request); this phone writes
// follows/iphone-<id>.json (requests: follow, unfollow, priority, folder).
// The Mac fetches the feeds and follows; the phone asks. Same shapes as the
// Mac's App/AppModel+FeedSync.swift.

struct FeedsFile: Codable {
    struct Row: Codable, Identifiable, Hashable {
        var id, title, url: String
        var site, folder, provider, priority: String?
        var enabled: Bool
        var items: Int
    }
    var schema: Int
    var feeds: [Row]
    /// Request id → "working", "followed", "failed" or "done".
    var requests: [String: String]
}

struct PhoneFeedRequest: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var input: String?
    var feedID: String?
    var folder: String?
    var priority: String?
    var at: Date
}

/// The Mac's `FeedPriority`, by raw value.
enum PhonePriority: String, CaseIterable {
    case must, normal, best, off
    var label: String {
        switch self {
        case .must: "Don't Miss"
        case .normal: "Normal"
        case .best: "Best Only"
        case .off: "Not in Today"
        }
    }
}

extension Store {
    private static var requestsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "follows-here.json")
    }
    private static var macFeedsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "feeds.json")
    }

    static func loadFeedRequests() -> [PhoneFeedRequest] {
        guard let data = try? Data(contentsOf: requestsURL) else { return [] }
        return (try? coder.1.decode([PhoneFeedRequest].self, from: data)) ?? []
    }

    static func loadMacFeeds() -> FeedsFile? {
        guard let data = try? Data(contentsOf: macFeedsURL) else { return nil }
        return try? coder.1.decode(FeedsFile.self, from: data)
    }

    /// Reads the Mac's list and writes this phone's requests.
    func syncFeeds(_ folder: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appending(path: "Deck/feeds.json"))
        if let data = coordinatedData(folder.appending(path: "Deck/feeds.json")),
           let file = try? Self.coder.1.decode(FeedsFile.self, from: data) {
            macFeeds = file
            try? data.write(to: Self.macFeedsURL, options: .atomic)
        }
        writeRequests(folder)
    }

    private func writeRequests(_ folder: URL) {
        guard !feedRequests.isEmpty, let data = try? Self.coder.0.encode(feedRequests) else { return }
        let dir = folder.appending(path: "follows", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: Self.deviceFile), options: .atomic)
    }

    func request(_ kind: String, input: String? = nil, feedID: String? = nil, folder: String? = nil, priority: String? = nil) {
        feedRequests.append(PhoneFeedRequest(id: UUID().uuidString.lowercased(), kind: kind, input: input,
                                             feedID: feedID, folder: folder, priority: priority, at: Date()))
        // Keep the file short: requests the Mac handled more than 30 days ago go.
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        feedRequests.removeAll { $0.at < cutoff && macFeeds?.requests[$0.id] != nil }
        if let data = try? Self.coder.0.encode(feedRequests) { try? data.write(to: Self.requestsURL, options: .atomic) }
        withFolder { writeRequests($0) }
    }

    /// "Waiting for your Mac", "Following", "No feed found", or nil when done.
    func status(of r: PhoneFeedRequest) -> String? {
        switch macFeeds?.requests[r.id] {
        case nil: "Waiting for your Mac"
        case "working": "Your Mac is looking"
        case "followed": "Following"
        case "failed": "No feed found"
        default: nil
        }
    }

    /// Unfollows and changes waiting for the Mac, so the list shows them now.
    var feedsShown: [FeedsFile.Row] {
        var rows = macFeeds?.feeds ?? []
        for r in feedRequests where macFeeds?.requests[r.id] == nil {
            guard let i = rows.firstIndex(where: { $0.id == r.feedID }) else { continue }
            switch r.kind {
            case "unfollow": rows.remove(at: i)
            case "priority": rows[i].priority = r.priority
            case "folder": rows[i].folder = r.folder
            default: break
            }
        }
        return rows
    }
}

struct FeedsView: View {
    @Environment(Store.self) private var store
    @State private var adding = false

    private var folders: [String] {
        Array(Set(store.feedsShown.compactMap(\.folder))).sorted()
    }

    var body: some View {
        List {
            let follows = store.feedRequests.filter { $0.kind == "follow" && store.macFeeds?.requests[$0.id] != "followed" }
            if !follows.isEmpty {
                Section("Follow requests") {
                    ForEach(follows) { r in
                        HStack {
                            Text(r.input ?? "").lineLimit(1)
                            Spacer()
                            Text(store.status(of: r) ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach([""] + folders, id: \.self) { folder in
                let rows = store.feedsShown.filter { ($0.folder ?? "") == folder }
                if !rows.isEmpty {
                    Section(folder.isEmpty ? "Feeds" : folder) {
                        ForEach(rows) { row($0) }
                    }
                }
            }
            if store.macFeeds == nil {
                Text("Your Mac has not shared its feeds yet. Open Sift on the Mac with iCloud Drive on.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Feeds")
        .refreshable { store.sync() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) { FollowSheet(folders: folders) }
    }

    private func row(_ f: FeedsFile.Row) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).lineLimit(1)
                Text(PhonePriority(rawValue: f.priority ?? "")?.label ?? "Auto")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(f.items)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .swipeActions {
            Button(role: .destructive) { store.request("unfollow", feedID: f.id) } label: { Label("Unfollow", systemImage: "minus.circle") }
        }
        .contextMenu {
            Menu("In Today") {
                Button("Auto") { store.request("priority", feedID: f.id) }
                ForEach(PhonePriority.allCases, id: \.self) { p in
                    Button(p.label) { store.request("priority", feedID: f.id, priority: p.rawValue) }
                }
            }
            Menu("Folder") {
                Button("No Folder") { store.request("folder", feedID: f.id) }
                ForEach(folders, id: \.self) { name in
                    Button(name) { store.request("folder", feedID: f.id, folder: name) }
                }
            }
            Button(role: .destructive) { store.request("unfollow", feedID: f.id) } label: { Label("Unfollow", systemImage: "minus.circle") }
        }
    }
}

/// Follow from the phone. The Mac finds the feed (the same providers as its
/// Follow sheet) and follows it; the request shows its state until then.
struct FollowSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folders: [String]
    @State private var input = ""
    @State private var folder = ""
    @FocusState private var focused: Bool

    private let examples = ["daringfireball.net", "r/swift", "@name.bsky.social", "@user@mastodon.social",
                            "youtube.com/@channel", "podcast: name", "news: words"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A site, r/subreddit, @handle, podcast: name…", text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).focused($focused)
                        .onSubmit(follow)
                    if !folders.isEmpty {
                        Picker("Folder", selection: $folder) {
                            Text("No folder").tag("")
                            ForEach(folders, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } footer: {
                    Text("Your Mac finds the feed and follows it. New items reach Today here once the Mac has checked it.")
                }
                Section("You can type") {
                    ForEach(examples, id: \.self) { e in
                        Button(e) { input = e; focused = true }.foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Follow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Follow", action: follow).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                focused = true
                if let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                   s.hasPrefix("http"), s.count < 500, !s.contains("\n") { input = s }
            }
        }
    }

    private func follow() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.request("follow", input: text, folder: folder.isEmpty ? nil : folder)
        dismiss()
    }
}
