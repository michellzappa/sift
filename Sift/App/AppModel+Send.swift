import Foundation

extension AppModel {
    // MARK: Send

    var destinations: [Destination] { state.destinations }

    func destination(_ id: String?) -> Destination? { id.flatMap { id in state.destinations.first { $0.id == id } } }

    /// The theme's default destination for this link, if any.
    func defaultDestination(for tab: SafariTab) -> Destination? {
        guard let theme = state.assignments[tab.url]?.project else { return nil }
        return destination(themes.first { $0.name == theme }?.sendTo)
    }

    func sentRecords(_ url: String) -> [SentRecord] { state.sent[url] ?? [] }

    func sentTabs(to id: String) -> [SafariTab] {
        let urls = state.sent.filter { $0.value.contains { $0.destination == id } }.map(\.key)
        return urls.compactMap { url in tabs.first { $0.url == url } ?? archive[url]?.asTab }
            .sorted { (state.sent[$0.url]?.last?.date ?? .distantPast) > (state.sent[$1.url]?.last?.date ?? .distantPast) }
    }

    func setDefaultDestination(_ id: String?, forTheme theme: String) {
        guard let i = state.extraProjects.firstIndex(where: { $0.name == theme }) else { return }
        state.extraProjects[i].sendTo = id
    }

    /// Sends one link now. A sent Safari tab is marked closable: it goes on
    /// the iPhone close list.
    func send(_ tab: SafariTab, to d: Destination) async {
        guard let sender = Senders.sender(for: d.kind), !sending.contains(tab.url) else { return }
        sending.insert(tab.url)
        defer { sending.remove(tab.url) }
        let p = previews[tab.url]
        let item = SendItem(
            url: tab.url,
            title: TabCard.title(tab, p),
            theme: state.assignments[tab.url].map { Project.displayName($0.project) } ?? "",
            note: note(for: tab.url) ?? "",
            summary: p?.failed == false ? p?.text ?? "" : "",
            text: library[tab.url]?.file.isEmpty == false ? Library.text(for: tab.url) ?? "" : "",
            site: tab.host, source: tab.source, saved: archive[tab.url]?.firstSeen ?? tab.lastViewed)
        do {
            let link = try await sender.send(item, to: d)
            state.sent[tab.url, default: []].append(SentRecord(destination: d.id, date: .now, link: link))
            if state.closeAfterSend, isOpenTab(tab), !state.closeQueue.contains(tab.url) {
                state.closeQueue.append(tab.url)
            }
        } catch {
            sendError = "\(d.name): \(error.localizedDescription)"
        }
    }

    /// Sends several links, one after another; stops at the first failure.
    func send(_ list: [SafariTab], to d: Destination) async {
        for tab in list where !sentRecords(tab.url).contains(where: { $0.destination == d.id }) {
            await send(tab, to: d)
            if sendError != nil { return }
        }
    }

    /// One Starlings destination per workspace, named "Starlings: <Name>".
    /// Project destinations from earlier builds are removed; their sent
    /// history stays in `state.sent`.
    func migrateStarlingsDestinations() async {
        var seen = Set<String>()
        var out: [Destination] = []
        for d in state.destinations {
            guard d.kind == "starlings", let origin = d.config["origin"] else { out.append(d); continue }
            if d.config["project"] != nil { continue }
            guard seen.insert(origin).inserted else { continue }
            var fixed = await Starlings.destination(for: origin)
            fixed.id = d.id
            out.append(fixed)
        }
        let removed = Set(state.destinations.map(\.id)).subtracting(out.map(\.id))
        if out != state.destinations {
            state.destinations = out
            for i in state.extraProjects.indices where state.extraProjects[i].sendTo.map(removed.contains) == true {
                state.extraProjects[i].sendTo = nil
            }
        }
    }

    func addDestination(_ d: Destination) {
        guard !state.destinations.contains(where: { $0.kind == d.kind && $0.config == d.config }) else { return }
        state.destinations.append(d)
    }

    func removeDestination(_ id: String) {
        state.destinations.removeAll { $0.id == id }
        for i in state.extraProjects.indices where state.extraProjects[i].sendTo == id { state.extraProjects[i].sendTo = nil }
    }

    /// Open tabs come from a Safari device or a Chrome profile; saved lists
    /// and imports do not.
    private func isOpenTab(_ tab: SafariTab) -> Bool {
        tab.source.hasPrefix("tabs") || tab.source.hasPrefix(ChromeReader.sourcePrefix)
    }
}
