import Foundation

/// Meaning on this Mac (Engine/Embeddings.swift): one background round per
/// library round. New or changed links and feed items of the last two weeks
/// get a vector; links that left are dropped from the store.
extension AppModel {
    func refreshEmbeddings() {
        guard !Demo.isOn, !isEmbedding else { return }
        var texts: [String: String] = [:]
        for l in savedLinks() {
            texts[l.url] = Meaning.text(title: l.title, preview: previews[l.url]?.text ?? "")
        }
        let since = Date().addingTimeInterval(-Trail.offeredDays * 86_400)
        for f in offeredFeeds where f.enabled {
            for e in FeedStore.entries(f.id) where (e.date ?? .distantPast) >= since {
                texts[e.url] = Meaning.text(title: FeedParser.Text.title(e.title, body: e.summary), preview: e.summary)
            }
        }
        let names = Set(themes.map(\.name))
        var themeOf: [String: String] = [:]
        for (url, a) in state.assignments where names.contains(a.project) { themeOf[url] = a.project }
        let battery = LocalModel.onBattery
        isEmbedding = true
        Task { [weak self] in
            let (space, changed) = await Task.detached(priority: .utility) { () -> (Meaning.Space, Bool) in
                var raw = Embeddings.load()
                let hashes = texts.mapValues(Meaning.hash)
                let todo = battery ? [] : Array(texts.filter { raw.hashes[$0.key] != hashes[$0.key] }.prefix(Embeddings.perRound))
                var changed = false
                if !todo.isEmpty, let embedder = Embedder() {
                    raw.model = embedder.identifier
                    for item in todo {
                        guard let v = embedder.vector(item.value) else { continue }
                        raw.vectors[item.key] = v
                        raw.hashes[item.key] = hashes[item.key]
                        changed = true
                    }
                }
                // Links and items that left: out of the store.
                let gone = raw.vectors.keys.filter { texts[$0] == nil }
                for u in gone { raw.vectors[u] = nil; raw.hashes[u] = nil }
                if changed || !gone.isEmpty { Embeddings.save(raw) }
                return (Meaning.Space(raw.vectors, themeOf: themeOf), changed)
            }.value
            guard let self else { return }
            self.embedSpace = space
            self.isEmbedding = false
            if changed { self.refreshToday() }
        }
    }

    /// The best theme by meaning for an address, if one clearly leads.
    func themeByMeaning(_ url: String) -> (name: String, cos: Double)? {
        embedSpace.unit[url].flatMap { embedSpace.theme(for: $0) }
    }
}
