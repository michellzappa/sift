import Foundation

// Agent-native Sift (issue #34). sift-mcp drops requests in
// Application Support/Sift/agent/requests (Shared/AgentRequests.swift); this
// file reads them, runs each through the same model function a button
// calls, and writes a result. sift-mcp never writes Sift's state.
//
// Owner's defaults (2026-11-15): themes apply without the review sheet;
// no delete theme (merge covers it); send is allowed and logged. Every
// request and outcome goes to agent/log.jsonl, shown in Settings.

extension AppModel {
    // MARK: Watching

    func startAgentWatcher() {
        guard !Demo.isOn, agentSource == nil else { return }
        AgentFiles.prepare()
        let fd = open(AgentFiles.requests.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in Task { @MainActor in self?.processAgentRequests() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        agentSource = source
        processAgentRequests()
    }

    /// Takes every waiting request once: the file is removed before the work
    /// starts, so a request never runs twice.
    func processAgentRequests() {
        guard !Demo.isOn, !agentBusy else { return }
        let files = ((try? FileManager.default.contentsOfDirectory(at: AgentFiles.requests, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return }
        agentBusy = true
        Task {
            defer {
                agentBusy = false
                // Requests that came in while these ran.
                processAgentRequests()
            }
            for file in files {
                guard let data = try? Data(contentsOf: file) else { continue }
                try? FileManager.default.removeItem(at: file)
                guard let request = try? AgentFiles.coder.1.decode(AgentRequest.self, from: data) else { continue }
                // Long jobs run on their own, so quick requests behind them
                // are not kept waiting.
                if Self.longJobs.contains(request.tool) {
                    Task { await handle(request) }
                } else {
                    await handle(request)
                }
            }
        }
    }

    private func finish(_ r: AgentRequest, _ status: String, _ text: String) {
        let result = AgentResult(id: r.id, tool: r.tool, status: status, text: text, at: Date())
        guard let data = try? AgentFiles.coder.0.encode(result) else { return }
        try? data.write(to: AgentFiles.results.appendingPathComponent("\(r.id).json"), options: .atomic)
        // The log: request and outcome on one line.
        struct Line: Encodable { let at: Date; let tool: String; let args: [String: [String]]; let status: String; let text: String }
        if let line = try? AgentFiles.coder.0.encode(Line(at: Date(), tool: r.tool, args: r.args, status: status, text: String(text.prefix(400)))),
           let handle = try? FileHandle(forWritingTo: AgentFiles.log) ?? {
               FileManager.default.createFile(atPath: AgentFiles.log.path, contents: nil)
               return try? FileHandle(forWritingTo: AgentFiles.log)
           }() {
            handle.seekToEndOfFile()
            handle.write(line + Data("\n".utf8))
            try? handle.close()
        }
        pruneAgentResults()
    }

    /// Results older than a week go.
    private func pruneAgentResults() {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        for file in (try? FileManager.default.contentsOfDirectory(at: AgentFiles.results, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if date < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    static let longJobs: Set<String> = ["sort_unsorted", "propose_new_themes", "check_feeds", "follow", "send"]

    // MARK: Lookups

    private func theme(_ name: String?) -> String? {
        guard let name else { return nil }
        return themes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name
    }

    private func feed(_ key: String?) -> Feed? {
        guard let key else { return nil }
        return state.feeds.first { $0.id == key || $0.url == key || $0.title.caseInsensitiveCompare(key) == .orderedSame }
    }

    private func link(_ url: String?) -> SafariTab? {
        guard let url else { return nil }
        return tabs.first { $0.url == url } ?? archive[url]?.asTab
    }

    private func priority(_ raw: String?) -> FeedPriority?? {
        guard let raw = raw?.lowercased() else { return .some(nil) }
        if raw == "auto" { return .some(nil) }
        let map: [String: FeedPriority] = ["must": .must, "don't miss": .must, "dont miss": .must, "normal": .normal,
                                           "best": .best, "best only": .best, "off": .off, "not in today": .off]
        guard let p = map[raw] else { return nil }
        return .some(p)
    }

    // MARK: Handling

    private func handle(_ r: AgentRequest) async {
        switch r.tool {
        // Themes
        case "merge_themes":
            guard let from = theme(r.first("from")), let into = theme(r.first("into")), from != into else {
                return finish(r, "failed", "Give two different theme names from list_themes.")
            }
            let n = count(from)
            mergeTheme(from, into: into)
            finish(r, "done", "Merged \"\(from)\" into \"\(into)\": \(n) links moved. \(themes.count) themes now.")
        case "rename_theme":
            guard let old = theme(r.first("name")), let new = r.first("to") else {
                return finish(r, "failed", "Give the theme's current name and the new name.")
            }
            guard theme(new) == nil else { return finish(r, "failed", "A theme named \"\(new)\" exists. Use merge_themes.") }
            renameTheme(old, to: new)
            finish(r, "done", "Renamed \"\(old)\" to \"\(new)\".")
        case "move_link":
            guard let tab = link(r.first("url")) else { return finish(r, "failed", "That URL is not in the library.") }
            let target = r.first("theme").flatMap { name in theme(name) ?? Project.buckets.first { $0 == name.lowercased() } }
            guard let target else { return finish(r, "failed", "Give a theme from list_themes, or drop, personal or errands.") }
            move(tab, to: target)
            finish(r, "done", "Moved \(tab.url) to \"\(target)\".")
        case "add_note":
            guard let url = r.first("url"), archive[url] != nil else { return finish(r, "failed", "That URL is not in the library.") }
            setNote(r.first("text") ?? "", for: url)
            finish(r, "done", r.first("text") == nil ? "Note removed." : "Note saved on \(url).")

        // Sorting
        case "sort_unsorted":
            let before = unsortedCount
            guard before > 0 else { return finish(r, "done", "Every link is in a theme.") }
            guard !themes.isEmpty else { return finish(r, "failed", "There are no themes yet. Create them in Sift first.") }
            finish(r, "started", "Sorting \(before) links. Call job_status with this id.")
            await sortUnsorted()
            if let error = sortError { return finish(r, "failed", "Sorting stopped: \(error)") }
            finish(r, "done", "Sorted \(before - unsortedCount) of \(before) links. \(unsortedCount) still unsorted.")
        case "propose_new_themes":
            guard unsortedCount > 0 else { return finish(r, "done", "Every link is in a theme; nothing to propose.") }
            finish(r, "started", "Claude is reading \(unsortedCount) unsorted links. Call job_status with this id.")
            guard let (proposals, urls) = await proposeNewThemes() else {
                return finish(r, "failed", sortError ?? "No proposal was made.")
            }
            agentProposals[r.id] = (proposals, urls)
            finish(r, "done", proposalText(r.id, proposals, urls))
        case "apply_theme_proposal":
            guard let id = r.first("proposal"), let stored = agentProposals[id] else {
                return finish(r, "failed", "No open proposal with that id. Run propose_new_themes first.")
            }
            var picked = stored.proposals
            let accept = Set(r.list("accept").map { $0.lowercased() })
            if !accept.isEmpty { picked = picked.filter { accept.contains($0.name.lowercased()) } }
            for rule in r.list("rename") {
                let parts = rule.components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, !parts[1].isEmpty else { continue }
                for i in picked.indices where picked[i].name.caseInsensitiveCompare(parts[0]) == .orderedSame && picked[i].kind != "existing" {
                    picked[i].name = parts[1]
                }
            }
            let before = themes.count
            applyNewThemes(picked, urls: stored.urls)
            agentProposals[id] = nil
            let filed = picked.reduce(0) { $0 + $1.itemIDs.count }
            finish(r, "done", "Added \(themes.count - before) themes and filed \(filed) links. \(unsortedCount) links still unsorted.")

        // Feeds
        case "follow":
            guard let input = r.first("input") else { return finish(r, "failed", "Give a site, feed address, r/name, @handle or podcast: name.") }
            guard let p = priority(r.first("priority")) else { return finish(r, "failed", "Priority is auto, must, normal, best or off.") }
            guard let found = await FeedProviders.resolve(input).first else { return finish(r, "failed", "No feed found for \(input).") }
            if let existing = state.feeds.first(where: { $0.url == found.url }) {
                return finish(r, "done", "Already following \(existing.title).")
            }
            addFeed(found, category: r.first("folder"), priority: p)
            finish(r, "done", "Following \(found.label ?? found.parsed.title) (\(found.url)), \(found.parsed.entries.count) items.")
        case "unfollow":
            guard let f = feed(r.first("feed")) else { return finish(r, "failed", "No followed feed matches. Use list_feeds.") }
            removeFeed(f)
            finish(r, "done", "Unfollowed \(f.title).")
        case "set_feed_priority":
            guard let f = feed(r.first("feed")) else { return finish(r, "failed", "No followed feed matches. Use list_feeds.") }
            guard let p = priority(r.first("priority")) else { return finish(r, "failed", "Priority is auto, must, normal, best or off.") }
            setPriority(f, p)
            finish(r, "done", "\(f.title): \(p?.label ?? "Auto") in Today.")
        case "move_feed":
            guard let f = feed(r.first("feed")) else { return finish(r, "failed", "No followed feed matches. Use list_feeds.") }
            moveFeed(f.id, to: r.first("folder"))
            finish(r, "done", "\(f.title) is now in \(r.first("folder") ?? "no folder").")
        case "check_feeds":
            finish(r, "started", "Checking \(state.feeds.count) feeds. Call job_status with this id.")
            await fetchFeeds(force: true)
            finish(r, "done", "Checked the feeds. Today has \(state.today?.picks.count ?? 0) picks.")

        // Links
        case "mark_seen":
            let urls = r.list("urls")
            guard !urls.isEmpty else { return finish(r, "failed", "Give one or more URLs.") }
            let seen = (r.first("seen") ?? "true").lowercased() != "false"
            setSeen(urls, seen)
            finish(r, "done", "Marked \(urls.count) link\(urls.count == 1 ? "" : "s") \(seen ? "seen" : "unseen").")
        case "keep":
            guard let url = r.first("url") else { return finish(r, "failed", "Give the URL of a Today or feed item.") }
            let pick = state.today?.picks.first { $0.url == url } ?? items(of: state.feeds).first { $0.url == url }
            guard let pick else { return finish(r, "failed", "That URL is not a Today or feed item.") }
            keep(pick)
            finish(r, "done", "Kept \(pick.title). It is now in the library.")
        case "send":
            guard let tab = link(r.first("url")) else { return finish(r, "failed", "That URL is not in the library.") }
            let key = r.first("destination") ?? ""
            guard let d = destinations.first(where: { $0.id == key || $0.name.caseInsensitiveCompare(key) == .orderedSame }) else {
                return finish(r, "failed", "No destination named \(key). Use list_destinations.")
            }
            await send(tab, to: d)
            let ok = state.sent[tab.url]?.contains { $0.destination == d.id } ?? false
            finish(r, ok ? "done" : "failed", ok ? "Sent \(tab.title) to \(d.name)." : "Sending to \(d.name) did not go through.")

        // Reads
        case "list_feeds":
            let rows = standings().sorted { ($0.feed.category ?? "", $0.feed.title) < ($1.feed.category ?? "", $1.feed.title) }
            guard !rows.isEmpty else { return finish(r, "done", "No feeds followed.") }
            finish(r, "done", "\(rows.count) feeds:\n" + rows.map { s in
                "- \(s.feed.title) — \(s.feed.url)\n  folder: \(s.feed.category ?? "none") · in Today: \(s.place) · \(s.rate) · \(s.learned)"
            }.joined(separator: "\n"))
        case "today":
            let picks = state.today?.picks ?? []
            guard !picks.isEmpty else { return finish(r, "done", "Today is empty.") }
            finish(r, "done", "\(picks.count) picks in Today, newest additions first:\n" + picks.map { p in
                "- \(p.title) — \(p.url)\n  \(p.feedTitle) · \(p.reason.isEmpty ? "" : p.reason + " · ")\(isSeen(p.url) ? "seen" : "unseen")\(isKept(p.url) ? " · kept" : "")"
            }.joined(separator: "\n"))
        case "unsorted":
            let limit = min(max(Int(r.first("limit") ?? "") ?? 50, 1), 500)
            let list = tabs.filter { state.assignments[$0.url] == nil }
            finish(r, "done", (list.count == 1 ? "1 link is" : "\(list.count) links are") + " in no theme" + (list.isEmpty ? "." : ", first \(min(limit, list.count)):\n")
                   + list.prefix(limit).map { "- \($0.title) — \($0.url)" }.joined(separator: "\n"))
        case "list_destinations":
            finish(r, "done", destinations.isEmpty ? "No Send destinations set up." :
                   destinations.map { "- \($0.name) (\($0.kind))\($0.detail.isEmpty ? "" : " · \($0.detail)")" }.joined(separator: "\n"))
        default:
            finish(r, "failed", "Sift does not know the tool \(r.tool).")
        }
    }

    private func proposalText(_ id: String, _ proposals: [Sorter.ThemeProposal], _ urls: [String]) -> String {
        func examples(_ p: Sorter.ThemeProposal) -> String {
            p.itemIDs.prefix(3).compactMap { i in urls.indices.contains(i) ? link(urls[i])?.title : nil }
                .map { String($0.prefix(60)) }.joined(separator: " · ")
        }
        var lines = ["Proposal \(id). Nothing is applied yet. Apply with apply_theme_proposal(proposal: \"\(id)\"), "
                     + "optionally with accept (names to keep; default all) and rename (\"Old => New\").", ""]
        let fresh = proposals.filter { $0.kind != "existing" }
        let existing = proposals.filter { $0.kind == "existing" }
        lines.append("New themes and buckets:")
        for p in fresh {
            lines.append("- \(p.name) [\(p.kind)] \(p.itemIDs.count) links: \(p.description)")
            lines.append("  e.g. \(examples(p))")
        }
        lines.append("")
        lines.append("Links that fit existing themes:")
        for p in existing { lines.append("- \(p.name): \(p.itemIDs.count) links") }
        return lines.joined(separator: "\n")
    }
}
