import Foundation
import SQLite3

/// Reads Safari's iCloud Tabs database read-only. Safari owns the file; Sift
/// never writes to it.
enum CloudTabsReader {
    enum Failure: LocalizedError {
        case noAccess
        case missing
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case .noAccess: "Sift needs Full Disk Access to read Safari's synced tabs."
            case .missing: "Safari's synced tab database was not found. Turn on Safari in iCloud settings."
            case .sqlite(let message): "Could not read the tab database: \(message)"
            }
        }
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.apple.Safari/Data/Library/Safari/CloudTabs.db")
    }

    static func devices() throws -> [SyncedDevice] {
        try query("""
            SELECT d.device_uuid, d.device_name, COUNT(t.tab_uuid)
            FROM cloud_tab_devices d LEFT JOIN cloud_tabs t ON t.device_uuid = d.device_uuid
            GROUP BY d.device_uuid ORDER BY COUNT(t.tab_uuid) DESC
            """, bind: []) { stmt in
            SyncedDevice(id: text(stmt, 0), name: text(stmt, 1), tabCount: Int(sqlite3_column_int(stmt, 2)))
        }
    }

    /// One row per unique URL on the device, most recently viewed first.
    static func tabs(deviceID: String) throws -> [SafariTab] {
        try query("""
            SELECT url, MAX(COALESCE(title, '')), MAX(last_viewed_time)
            FROM cloud_tabs WHERE device_uuid = ?
            GROUP BY url ORDER BY MAX(last_viewed_time) DESC
            """, bind: [deviceID]) { stmt in
            let seconds = sqlite3_column_double(stmt, 2)
            return SafariTab(
                url: text(stmt, 0),
                title: text(stmt, 1).replacingOccurrences(of: "\n", with: " "),
                lastViewed: seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil
            )
        }
    }

    private static func query<T>(_ sql: String, bind: [String], row: (OpaquePointer) -> T) throws -> [T] {
        let path = databaseURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { throw Failure.missing }
        guard FileManager.default.isReadableFile(atPath: path) else { throw Failure.noAccess }

        var db: OpaquePointer?
        let uri = "file:\(path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            let code = sqlite3_errcode(db)
            sqlite3_close(db)
            throw code == SQLITE_AUTH || code == SQLITE_PERM || code == SQLITE_CANTOPEN ? Failure.noAccess : Failure.sqlite("open failed (\(code))")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let message = String(cString: sqlite3_errmsg(db))
            throw message.contains("authorization") ? Failure.noAccess : Failure.sqlite(message)
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in bind.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient)
        }

        var rows: [T] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW { rows.append(row(stmt)); continue }
            if step == SQLITE_DONE { break }
            let message = String(cString: sqlite3_errmsg(db))
            throw message.contains("authorization") ? Failure.noAccess : Failure.sqlite(message)
        }
        return rows
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, column) else { return "" }
        return String(cString: c)
    }
}
