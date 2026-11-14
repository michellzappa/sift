import Foundation
import SQLite3

/// Full-text search over everything Sift keeps: titles, captured page text,
/// YouTube and reel transcripts, captions and previews. One SQLite file with
/// an FTS5 table, rebuilt from the library and archive when they change:
/// ~/Library/Application Support/Sift/search.sqlite
///
/// The `sift-mcp` tool inside Sift.app reads the same file, read-only, so
/// Claude can search the library. Keep the schema in step with SiftMCP
/// (`links.summary` is read by its `search` and `get_link`).
enum SearchIndex {
    static var url: URL { StateFile.url.deletingLastPathComponent().appending(path: "search.sqlite") }

    struct Doc: Sendable {
        let url, title, theme, source, kind: String
        let saved: Date
        /// Library file name, or "" when only metadata is kept.
        let file: String
        let also: [String]
        /// Used when there is no library file.
        let fallback: String
        /// The user's own note on the link.
        let note: String
        /// The on-device summary, or "".
        var summary: String = ""
    }

    struct Theme: Sendable {
        let name, summary, notes, memory: String
        let links: Int
    }

    struct Hit: Sendable {
        let url: String
        let snippet: String
    }

    /// Writes a new index next to the old one and swaps it in, so readers
    /// (the app, sift-mcp) never see a half-built file.
    static func rebuild(docs: [Doc], themes: [Theme]) {
        let temp = url.deletingLastPathComponent().appending(path: "search.sqlite.new")
        try? FileManager.default.removeItem(at: temp)
        var db: OpaquePointer?
        guard sqlite3_open(temp.path(percentEncoded: false), &db) == SQLITE_OK, let db else { return }
        defer { sqlite3_close(db) }
        let schema = """
            PRAGMA journal_mode=OFF;
            CREATE TABLE links(url TEXT PRIMARY KEY, title TEXT, theme TEXT, source TEXT, kind TEXT, saved TEXT, file TEXT, also TEXT, summary TEXT);
            CREATE VIRTUAL TABLE fts USING fts5(url UNINDEXED, title, body, theme, summary, tokenize='unicode61 remove_diacritics 2');
            CREATE TABLE themes(name TEXT PRIMARY KEY, summary TEXT, notes TEXT, memory TEXT, links INTEGER);
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
            BEGIN;
            """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { return }
        let iso = ISO8601DateFormatter()
        let link = prepare(db, "INSERT OR REPLACE INTO links VALUES (?,?,?,?,?,?,?,?,?)")
        let fts = prepare(db, "INSERT INTO fts VALUES (?,?,?,?,?)")
        for d in docs {
            let text = d.file.isEmpty ? d.fallback : (Library.text(for: d.url) ?? d.fallback)
            let body = d.note.isEmpty ? text : "Note: \(d.note)\n\n\(text)"
            run(link, [d.url, d.title, d.theme, d.source, d.kind, iso.string(from: d.saved), d.file, d.also.joined(separator: "\n"), d.summary])
            run(fts, [d.url, d.title, body, ([d.theme] + d.also).joined(separator: " "), d.summary])
        }
        sqlite3_finalize(link)
        sqlite3_finalize(fts)
        let theme = prepare(db, "INSERT OR REPLACE INTO themes VALUES (?,?,?,?,?)")
        for t in themes {
            run(theme, [t.name, t.summary, t.notes, t.memory], int: t.links)
        }
        sqlite3_finalize(theme)
        let meta = prepare(db, "INSERT INTO meta VALUES ('built', ?)")
        run(meta, [iso.string(from: .now)])
        sqlite3_finalize(meta)
        guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: temp)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.moveItem(at: temp, to: url)
        }
    }

    /// Best matches first. Words must all match; when nothing does, any word.
    static func search(_ query: String, limit: Int = 300) -> [Hit] {
        let words = query.split { !$0.isLetter && !$0.isNumber }.map { "\"\($0)\"" }
        guard !words.isEmpty else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path(percentEncoded: false), &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }
        let sql = """
            SELECT url, snippet(fts, 2, '', '', ' … ', 20) FROM fts WHERE fts MATCH ?
            ORDER BY bm25(fts, 0, 5.0, 1.0, 2.0) LIMIT \(limit)
            """
        for match in [words.joined(separator: " "), words.joined(separator: " OR ")] {
            guard let stmt = prepare(db, sql) else { return [] }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, match)
            var hits: [Hit] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                hits.append(Hit(url: column(stmt, 0), snippet: column(stmt, 1)))
            }
            if !hits.isEmpty || words.count == 1 { return hits }
        }
        return []
    }

    // MARK: SQLite helpers

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        return sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK ? stmt : nil
    }

    private static func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, transient)
    }

    private static func run(_ stmt: OpaquePointer?, _ values: [String], int: Int? = nil) {
        guard let stmt else { return }
        for (i, v) in values.enumerated() { bind(stmt, Int32(i + 1), v) }
        if let int { sqlite3_bind_int64(stmt, Int32(values.count + 1), Int64(int)) }
        sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    private static func column(_ stmt: OpaquePointer, _ i: Int32) -> String {
        sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
    }
}
