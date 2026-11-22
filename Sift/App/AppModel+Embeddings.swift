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
        let texts0 = texts, themes0 = themeOf
        Task { [weak self] in
            let (space, changed) = await Self.makeSpace(texts: texts0, themeOf: themes0, battery: battery)
            guard let self else { return }
            self.embedSpace = space
            self.isEmbedding = false
            self.refreshThemeGraph()
            if changed { self.refreshToday() }
        }
    }

    /// Off the main actor: vectors for what changed, then the space.
    nonisolated private static func makeSpace(texts: [String: String], themeOf: [String: String], battery: Bool) async -> (Meaning.Space, Bool) {
            await Task.detached(priority: .utility) { () -> (Meaning.Space, Bool) in
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
    }

    /// The best theme by meaning for an address, if one clearly leads.
    func themeByMeaning(_ url: String) -> (name: String, cos: Double)? {
        embedSpace.unit[url].flatMap { embedSpace.theme(for: $0) }
    }
}

/// Subterms and the creator graph (Engine/ThemeGraph.swift), after each
/// embeddings round; then the sub-clusters (AppModel+SubClusters).
extension AppModel {
    func refreshThemeGraph() {
        var texts: [String: [String]] = [:]
        for l in savedLinks() {
            guard let t = l.theme else { continue }
            texts[t, default: []].append(l.title + " " + String((previews[l.url]?.text ?? "").prefix(300)))
        }
        let nodes = creators.map { CreatorGraph.Node(id: $0.id, saves: $0.saves, followed: $0.feedID != nil, score: $0.score) }
        let vectors = embedSpace.unit
        Task { [weak self] in
            let (terms, graph) = await Self.computeThemeGraph(texts: texts, nodes: nodes, vectors: vectors)
            guard let self else { return }
            self.themeTerms = terms
            self.creatorSimilar = graph.similar
            self.creatorRank = graph.rank
            self.writeCreatorsForPhone()
            self.refreshSubClusters()
        }
    }

    nonisolated private static func computeThemeGraph(texts: [String: [String]], nodes: [CreatorGraph.Node],
                                                      vectors: [String: [Float]]) async -> ([String: [String]], CreatorGraph.Result) {
        await Task.detached(priority: .utility) {
            (Subterms.build(texts), CreatorGraph.build(nodes, vectors: vectors))
        }.value
    }
}
