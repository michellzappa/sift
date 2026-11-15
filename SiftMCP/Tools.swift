import Foundation

/// The four read-only tools over the Sift library.
enum Tools {
    struct Outcome {
        var text: String
        var isError = false
    }

    static let names: Set<String> = Set(["search", "get_link", "list_themes", "theme_links"]).union(AgentCalls.names)

    static let instructions = """
        Sift is the user's personal library of saved links: Safari tabs from their devices, \
        Safari Reading List, Instagram saved posts, X posts, YouTube videos and imported link lists. \
        Sift captures page text and video or reel transcripts, and groups the links into themes. \
        Use `search` to find material by words, `list_themes` to see how the library is organised, \
        `theme_links` to list one theme, and `get_link` to read the captured text of one link. \
        Other tools change Sift for the user (merge or rename themes, file links, sort, propose themes, \
        follow feeds, mark seen, keep, send): the running Sift app does each change and says what it did. \
        Search leaves out dropped links and errands unless include_hidden is true, and marks links the user \
        kept, sent, noted or has seen.
        """

    private static let libraryNote = "This is the user's personal Sift library of saved links "
        + "(Safari tabs, Reading List, Instagram, X, YouTube, imports) with captured page text "
        + "and transcripts, grouped into themes."

    static var definitions: [[String: Any]] {
        [
            [
                "name": "search",
                "title": "Search the Sift library",
                "description": libraryNote + " Full-text search over titles, captured page text, "
                    + "transcripts and theme names. All words must match; when nothing matches, any word may match. "
                    + "Returns the best hits with title, URL, theme, source, saved date, a one-paragraph summary "
                    + "when Sift has one, and a text snippet (matches in **bold**). "
                    + "Use get_link with a URL to read the whole text.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Words to look for. Plain words, no operators."],
                        "theme": ["type": "string", "description": "Optional theme name (from list_themes) to search only in that theme."],
                        "limit": ["type": "integer", "minimum": 1, "maximum": 50, "default": 10,
                                  "description": "Number of hits to return (1 to 50, default 10)."],
                        "include_hidden": ["type": "boolean", "default": false,
                                           "description": "Also return links the user dropped as noise and errands (transactional pages). Default false."],
                    ],
                    "required": ["query"],
                ] as [String: Any],
                "annotations": readOnly,
            ],
            [
                "name": "get_link",
                "title": "Read one saved link",
                "description": libraryNote + " Returns one link's metadata (title, theme, related themes, "
                    + "source, kind, saved date), a one-paragraph summary when Sift has one, "
                    + "and the captured page text or transcript as Markdown, "
                    + "up to 40,000 characters. Pass the URL exactly as search or theme_links returned it.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "url": ["type": "string", "description": "The link's URL, as returned by search or theme_links."],
                    ],
                    "required": ["url"],
                ] as [String: Any],
                "annotations": readOnly,
            ],
            [
                "name": "list_themes",
                "title": "List Sift themes",
                "description": libraryNote + " Lists every theme with its number of links, its summary, "
                    + "and the user's own notes and memory for the theme when present. "
                    + "Start here to see what the user collects and which theme names exist.",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any](),
                ] as [String: Any],
                "annotations": readOnly,
            ],
            [
                "name": "theme_links",
                "title": "List links in a theme",
                "description": libraryNote + " Lists the links in one theme (its own links and links that "
                    + "also feed it), newest saved first, with title, URL, source and saved date.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "theme": ["type": "string", "description": "Theme name, as list_themes returns it."],
                        "limit": ["type": "integer", "minimum": 1, "maximum": 200, "default": 50,
                                  "description": "Number of links to return (1 to 200, default 50)."],
                    ],
                    "required": ["theme"],
                ] as [String: Any],
                "annotations": readOnly,
            ],
        ] + AgentCalls.definitions
    }

    private static var readOnly: [String: Any] {
        ["readOnlyHint": true, "openWorldHint": false]
    }

    static func call(_ name: String, arguments: [String: Any]) -> Outcome {
        if AgentCalls.names.contains(name) { return AgentCalls.call(name, arguments: arguments) }
        do {
            switch name {
            case "search": return try search(arguments)
            case "get_link": return try getLink(arguments)
            case "list_themes": return try listThemes()
            case "theme_links": return try themeLinks(arguments)
            default: return Outcome(text: "Unknown tool: \(name)", isError: true)
            }
        } catch {
            Log.write("\(name): \(error.message)")
            return Outcome(text: error.message, isError: true)
        }
    }

    // MARK: - search

    private static func search(_ arguments: [String: Any]) throws(IndexError) -> Outcome {
        let query = string(arguments["query"])
        let words = matchWords(query)
        guard !words.isEmpty else {
            return Outcome(text: "Give a query with at least one word.", isError: true)
        }
        let theme = string(arguments["theme"])
        let limit = integer(arguments["limit"], default: 10, max: 50)
        let includeHidden = (arguments["include_hidden"] as? Bool) ?? false
        let index = try Index()
        let hasSignals = hasColumn(index, "signals")

        var sql = """
            SELECT coalesce(links.title, fts.title) AS title, fts.url AS url,
                   coalesce(links.theme, fts.theme) AS theme, links.source AS source, links.saved AS saved,
                   snippet(fts, 2, '**', '**', ' … ', 24) AS snippet\(summaryColumn(index))\(hasSignals ? ", links.signals AS signals" : "")
            FROM fts LEFT JOIN links ON links.url = fts.url
            WHERE fts MATCH ?
            """
        var filter: [Any] = []
        if !theme.isEmpty {
            sql += " AND " + inTheme
            filter = [theme, theme]
        }
        // Noise and errands stay out unless asked for (owner, 2026-11-15).
        if !includeHidden { sql += " AND coalesce(links.theme, '') NOT IN ('drop', 'errands')" }
        // What the user kept, sent or noted ranks first; seen a little.
        let boost = hasSignals ? """
             - (CASE WHEN links.signals LIKE '%kept%' OR links.signals LIKE '%sent%' OR links.signals LIKE '%noted%' THEN 2.0
                     WHEN links.signals LIKE '%seen%' THEN 0.5 ELSE 0 END)
            """ : ""
        sql += " ORDER BY bm25(fts, 0, 5.0, 1.0, 2.0)\(boost) LIMIT ?"

        var hits = try index.rows(sql, [words.joined(separator: " ")] + filter + [limit])
        var loose = false
        if hits.isEmpty && words.count > 1 {
            hits = try index.rows(sql, [words.joined(separator: " OR ")] + filter + [limit])
            loose = true
        }

        let scope = theme.isEmpty ? "" : " in theme \"\(theme)\""
        guard !hits.isEmpty else {
            return Outcome(text: "No links match \"\(query)\"\(scope).")
        }
        var lines = ["\(hits.count) result\(hits.count == 1 ? "" : "s") for \"\(query)\"\(scope)"
            + (loose ? " (no link has all the words; these match some of them)" : "") + ":", ""]
        for (number, hit) in hits.enumerated() {
            lines.append("\(number + 1). **\(title(hit))**")
            lines.append("   \(hit["url"] ?? "")")
            lines.append("   " + facts([hit["theme"], hit["source"], day(hit["saved"]), signals(hit["signals"])]))
            let summary = oneLine(hit["summary"] ?? "")
            if !summary.isEmpty { lines.append("   Summary: \(summary)") }
            let snippet = oneLine(hit["snippet"] ?? "")
            if !snippet.isEmpty { lines.append("   \(snippet)") }
        }
        return Outcome(text: lines.joined(separator: "\n"))
    }

    // MARK: - get_link

    private static func getLink(_ arguments: [String: Any]) throws(IndexError) -> Outcome {
        let url = string(arguments["url"])
        guard !url.isEmpty else { return Outcome(text: "Give the link's url.", isError: true) }
        let index = try Index()
        let sql = "SELECT url, title, theme, source, kind, saved, file, also\(summaryColumn(index))\(hasColumn(index, "signals") ? ", signals" : "") FROM links WHERE url = ? LIMIT 1"
        var rows = try index.rows(sql, [url])
        if rows.isEmpty {
            let other = url.hasSuffix("/") ? String(url.dropLast()) : url + "/"
            rows = try index.rows(sql, [other])
        }
        guard let link = rows.first else {
            return Outcome(text: "This URL is not in the Sift library: \(url). Use search to find links.", isError: true)
        }

        var lines = ["# \(title(link))", "", "- URL: \(link["url"] ?? url)"]
        if let theme = link["theme"], !theme.isEmpty { lines.append("- Theme: \(theme)") }
        let also = (link["also"] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if !also.isEmpty { lines.append("- Also related to: \(also.joined(separator: ", "))") }
        if let source = link["source"], !source.isEmpty { lines.append("- Source: \(source)") }
        if let kind = link["kind"], !kind.isEmpty { lines.append("- Kind: \(kind)") }
        if let saved = day(link["saved"]) { lines.append("- Saved: \(saved)") }
        if let marks = signals(link["signals"]) { lines.append("- User: \(marks)") }
        lines.append("")
        let summary = oneLine(link["summary"] ?? "")
        if !summary.isEmpty { lines += ["Summary: \(summary)", ""] }

        let file = link["file"] ?? ""
        guard !file.isEmpty, let body = libraryText(file) else {
            lines.append("Sift has saved only the metadata for this link; it has no captured text.")
            return Outcome(text: lines.joined(separator: "\n"))
        }
        let limit = 40_000
        if body.count > limit {
            lines.append(String(body.prefix(limit)))
            lines.append("")
            lines.append("[Text cut at \(limit) of \(body.count) characters.]")
        } else {
            lines.append(body)
        }
        return Outcome(text: lines.joined(separator: "\n"))
    }

    /// The library file's text without its YAML front matter. Refuses names
    /// that resolve outside the library folder.
    private static func libraryText(_ file: String) -> String? {
        let root = Paths.library.standardizedFileURL.path
        let path = Paths.library.appendingPathComponent(file).standardizedFileURL.path
        guard path.hasPrefix(root + "/"),
              let data = FileManager.default.contents(atPath: path)
        else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("---\n") || text.hasPrefix("---\r\n") {
            let rest = text.drop(while: { $0 != "\n" }).dropFirst()
            var offset = rest.startIndex
            var found = false
            while offset < rest.endIndex {
                let lineEnd = rest[offset...].firstIndex(of: "\n") ?? rest.endIndex
                let line = rest[offset..<lineEnd].trimmingCharacters(in: .whitespaces)
                let next = lineEnd < rest.endIndex ? rest.index(after: lineEnd) : rest.endIndex
                if line == "---" || line == "---\r" {
                    text = String(rest[next...])
                    found = true
                    break
                }
                offset = next
            }
            if !found { text = String(rest) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - list_themes

    private static func listThemes() throws(IndexError) -> Outcome {
        let index = try Index()
        let themes = try index.rows("SELECT name, summary, notes, memory, links FROM themes ORDER BY name COLLATE NOCASE")
        guard !themes.isEmpty else {
            return Outcome(text: "Sift has no themes yet. The user creates them in Sift.")
        }
        var lines = ["\(themes.count) theme\(themes.count == 1 ? "" : "s") in the Sift library:", ""]
        for theme in themes {
            let count = Int(theme["links"] ?? "") ?? 0
            lines.append("## \(theme["name"] ?? "") (\(count) link\(count == 1 ? "" : "s"))")
            for (label, key) in [("Summary", "summary"), ("Notes", "notes"), ("Memory", "memory")] {
                let value = (theme[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { lines.append("\(label): \(value)") }
            }
            lines.append("")
        }
        return Outcome(text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - theme_links

    private static func themeLinks(_ arguments: [String: Any]) throws(IndexError) -> Outcome {
        let theme = string(arguments["theme"])
        guard !theme.isEmpty else { return Outcome(text: "Give a theme name (see list_themes).", isError: true) }
        let limit = integer(arguments["limit"], default: 50, max: 200)
        let index = try Index()
        let where_ = "FROM links WHERE " + inTheme
        let total = Int(try index.rows("SELECT count(*) AS n " + where_, [theme, theme]).first?["n"] ?? "") ?? 0
        guard total > 0 else {
            return Outcome(text: "No links in a theme named \"\(theme)\". Use list_themes for the theme names.")
        }
        let links = try index.rows("SELECT title, url, source, saved " + where_ + " ORDER BY saved DESC LIMIT ?",
                                   [theme, theme, limit])
        var header = "\(total) link\(total == 1 ? "" : "s") in theme \"\(theme)\""
        if links.count < total { header += ", newest \(links.count) shown" }
        var lines = [header + ":", ""]
        for (number, link) in links.enumerated() {
            lines.append("\(number + 1). **\(title(link))**")
            lines.append("   \(link["url"] ?? "")")
            lines.append("   " + facts([link["source"], day(link["saved"])]))
        }
        return Outcome(text: lines.joined(separator: "\n"))
    }

    // MARK: - helpers

    private static func hasColumn(_ index: Index, _ name: String) -> Bool {
        ((try? index.rows("PRAGMA table_info(links)")) ?? []).contains { $0["name"] == name }
    }

    /// "kept, seen" as the user would say it, or nil.
    private static func signals(_ value: String?) -> String? {
        let words = (value ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        return words.isEmpty ? nil : words.joined(separator: ", ")
    }

    /// ", links.summary AS summary" when the index has the column. An index
    /// built by an older Sift has none; the tools then leave the summary out.
    private static func summaryColumn(_ index: Index) -> String {
        let columns = (try? index.rows("PRAGMA table_info(links)")) ?? []
        return columns.contains { $0["name"] == "summary" } ? ", links.summary AS summary" : ""
    }

    /// A link is in a theme when it is its main theme or one of its related
    /// themes (`also`, joined by newlines). Case-insensitive. Binds the theme twice.
    private static let inTheme = "(links.theme = ? COLLATE NOCASE OR instr(lower(char(10) || links.also || char(10)), lower(char(10) || ? || char(10))) > 0)"

    /// Splits user text into words and quotes each as an FTS5 string, so no
    /// user text is read as FTS5 syntax. Words without a letter or digit are
    /// dropped (they would make an empty phrase).
    static func matchWords(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    }

    private static func string(_ value: Any?) -> String {
        ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func integer(_ value: Any?, default fallback: Int, max: Int) -> Int {
        var number = fallback
        if let value = value as? NSNumber { number = value.intValue }
        else if let value = value as? String, let parsed = Int(value) { number = parsed }
        return Swift.min(Swift.max(number, 1), max)
    }

    private static func title(_ row: [String: String]) -> String {
        let value = oneLine(row["title"] ?? "")
        return value.isEmpty ? (row["url"] ?? "Untitled") : value
    }

    /// The date part of an ISO 8601 timestamp.
    private static func day(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return String(value.prefix(10))
    }

    private static func facts(_ values: [String?]) -> String {
        values.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
