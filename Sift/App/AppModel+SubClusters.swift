import Foundation

/// A theme's list narrowed to one of its parts.
struct SubClusterFilter: Equatable {
    var theme: String
    var name: String
}

/// Sub-clusters (Engine/SubClusters.swift), after each theme graph round:
/// the math runs detached, names come from the on-device model (cached by
/// theme + members), else from TF-IDF words.
extension AppModel {
    func refreshSubClusters() {
        guard !isNamingSubClusters else { return }
        var urlsOf: [String: [String]] = [:]
        var texts: [String: String] = [:]
        var titles: [String: String] = [:]
        for l in savedLinks() {
            guard let t = l.theme, embedSpace.unit[l.url] != nil else { continue }
            urlsOf[t, default: []].append(l.url)
            titles[l.url] = l.title
            texts[l.url] = l.title + " " + String((previews[l.url]?.text ?? "").prefix(300))
        }
        let vectors = embedSpace.unit
        let urls0 = urlsOf, texts0 = texts
        let canAsk = !Demo.isOn && !LocalModel.onBattery && LocalModel.isAvailable
        isNamingSubClusters = true
        Task { [weak self] in
            let computed = await Self.computeSubClusters(urlsOf: urls0, vectors: vectors, texts: texts0)
            guard let self else { return }
            var result: [String: [SubCluster]] = [:]
            var store = SubClusterStore(names: self.subClusterNames, parts: self.subClusters)
            for theme in computed.keys.sorted() {
                let (parts, fallback) = computed[theme]!
                let previous = self.subClusters[theme] ?? []
                var names: [String] = []
                for (i, part) in parts.enumerated() {
                    let key = SubClusters.key(theme: theme, urls: part.urls)
                    if let cached = store.names[key] { names.append(cached); continue }
                    if let old = previous.first(where: { SubClusters.overlap($0.urls, part.urls) >= SubClusters.keepNameOverlap }),
                       store.names.values.contains(old.name) {
                        store.names[key] = old.name
                        names.append(old.name)
                        continue
                    }
                    if canAsk, let name = await LocalModel.nameCluster(
                        theme: theme, titles: part.urls.prefix(SubClusters.titlesForName).compactMap { titles[$0] }) {
                        store.names[key] = name
                        names.append(name)
                    } else {
                        // Not cached: the model names it on a later round.
                        names.append(fallback[i])
                    }
                }
                let unique = SubClusters.unique(names)
                result[theme] = parts.enumerated().map { SubCluster(name: unique[$0.offset], urls: $0.element.urls) }
            }
            // Names of parts that no longer exist go, so the file stays small.
            let live = Set(result.flatMap { theme, parts in parts.map { SubClusters.key(theme: theme, urls: $0.urls) } })
            store.names = store.names.filter { live.contains($0.key) }
            store.parts = result
            self.subClusterNames = store.names
            if self.subClusters != result { self.subClusters = result }
            if let f = self.subClusterFilter, !(result[f.theme] ?? []).contains(where: { $0.name == f.name }) {
                self.subClusterFilter = nil
            }
            if !Demo.isOn { store.save() }
            self.isNamingSubClusters = false
            self.writeCreatorsForPhone()
        }
    }

    nonisolated private static func computeSubClusters(urlsOf: [String: [String]], vectors: [String: [Float]],
                                                       texts: [String: String]) async -> [String: ([SubClusters.Part], [String])] {
        await Task.detached(priority: .utility) {
            var out: [String: ([SubClusters.Part], [String])] = [:]
            for (theme, urls) in urlsOf {
                let parts = SubClusters.split(urls, vectors: vectors)
                guard parts.count >= 2 else { continue }
                out[theme] = (parts, SubClusters.fallbackNames(theme: theme, parts: parts, texts: texts))
            }
            return out
        }.value
    }

    /// The members of the part a theme's list is filtered to, if any.
    func subClusterMembers(theme: String) -> Set<String>? {
        guard let f = subClusterFilter, f.theme == theme,
              let part = subClusters[theme]?.first(where: { $0.name == f.name }) else { return nil }
        return Set(part.urls)
    }
}
