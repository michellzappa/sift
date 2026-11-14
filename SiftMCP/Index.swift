import Foundation
import SQLite3

/// Where the app keeps what this server reads.
enum Paths {
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Sift", isDirectory: true)
    static let index = support.appendingPathComponent("search.sqlite")
    static let library = support.appendingPathComponent("Library", isDirectory: true)
}

struct IndexError: Error {
    let message: String
}

/// A read-only connection to search.sqlite. Opened per tool call, so a
/// rebuilt index is picked up without restarting the server.
final class Index {
    private var db: OpaquePointer?

    static let missingMessage = "Sift has not built its search index yet. Open Sift once."

    init() throws(IndexError) {
        guard FileManager.default.fileExists(atPath: Paths.index.path) else {
            throw IndexError(message: Self.missingMessage)
        }
        let status = sqlite3_open_v2(Paths.index.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK else {
            let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
            sqlite3_close(db)
            db = nil
            throw IndexError(message: "Could not open the Sift search index: \(detail)")
        }
        sqlite3_busy_timeout(db, 3000)
    }

    deinit {
        sqlite3_close(db)
    }

    /// Runs one query. Values are bound as text or integer; rows come back as
    /// column name to text (NULL becomes "").
    func rows(_ sql: String, _ values: [Any] = []) throws(IndexError) -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IndexError(message: "Index query failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let position = Int32(offset + 1)
            if let number = value as? Int {
                sqlite3_bind_int64(statement, position, Int64(number))
            } else {
                sqlite3_bind_text(statement, position, "\(value)", -1, transient)
            }
        }
        var result: [[String: String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw IndexError(message: "Index query failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                if let text = sqlite3_column_text(statement, column) {
                    row[name] = String(cString: text)
                } else {
                    row[name] = ""
                }
            }
            result.append(row)
        }
        return result
    }
}
