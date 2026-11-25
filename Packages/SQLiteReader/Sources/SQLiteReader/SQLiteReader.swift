import Foundation
import SQLite3

/// A value bound to a query parameter.
public enum SQLiteValue: Sendable {
    case text(String), integer(Int64), real(Double), null
}

/// One result row, read by column index.
public struct SQLiteRow: Sendable {
    fileprivate let values: [SQLiteValue]

    public subscript(text index: Int) -> String? {
        guard values.indices.contains(index), case .text(let value) = values[index] else { return nil }
        return value
    }

    public subscript(integer index: Int) -> Int64? {
        guard values.indices.contains(index) else { return nil }
        switch values[index] {
        case .integer(let value): return value
        case .real(let value): return Int64(exactly: value.rounded(.down))
        default: return nil
        }
    }

    public subscript(real index: Int) -> Double? {
        guard values.indices.contains(index) else { return nil }
        switch values[index] {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }
}

public enum SQLiteReadError: Error, Equatable, Sendable {
    case open(path: String, code: Int32, message: String)
    case query(path: String, sql: String, message: String)
}

/// Reads another program's SQLite database (a harness's store) without ever writing it. It opens read-only, which
/// also reads the write-ahead log where harnesses keep their latest rows; when that cannot open (no `-shm` and no
/// right to create it), it falls back to `immutable=1`, which skips the log. Every call opens and closes its own
/// connection, so a store that changes between calls is read fresh (spec F6).
public struct SQLiteReader: Sendable {
    /// A harness writing at that moment holds the lock briefly; longer than this is reported, not waited out.
    static let busyTimeoutMilliseconds: Int32 = 100

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func rows(_ sql: String, _ bindings: [SQLiteValue] = []) throws(SQLiteReadError) -> [SQLiteRow] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw .open(path: url.path, code: SQLITE_CANTOPEN, message: "no such file")
        }
        do {
            return try run(sql, bindings, options: "mode=ro")
        } catch let failure {
            guard failure.code == SQLITE_CANTOPEN else { throw failure.error }
            do {
                return try run(sql, bindings, options: "mode=ro&immutable=1")
            } catch {
                throw error.error
            }
        }
    }

    /// The table's column names; empty when the table does not exist.
    public func columns(of table: String) throws(SQLiteReadError) -> Set<String> {
        Set(try rows("select name from pragma_table_info(?)", [.text(table)]).compactMap { $0[text: 0] })
    }

    /// A failure with SQLite's primary result code, so a store that cannot be opened read-only (error 14, at open
    /// or at the first read) is retried as immutable.
    private struct Failure: Error {
        let code: Int32
        let error: SQLiteReadError
    }

    private func run(_ sql: String, _ bindings: [SQLiteValue], options: String) throws(Failure) -> [SQLiteRow] {
        let connection = try open(options: options)
        defer { sqlite3_close_v2(connection) }
        return try query(connection, sql, bindings)
    }

    private func open(options: String) throws(Failure) -> OpaquePointer {
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        let location = (components.string ?? "file:" + url.path) + "?" + options
        var connection: OpaquePointer?
        let code = sqlite3_open_v2(location, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard code == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close_v2(connection)
            throw Failure(code: code & 0xFF, error: .open(path: url.path, code: code, message: message))
        }
        sqlite3_busy_timeout(connection, Self.busyTimeoutMilliseconds)
        return connection
    }

    private func query(_ connection: OpaquePointer, _ sql: String, _ bindings: [SQLiteValue])
        throws(Failure) -> [SQLiteRow]
    {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw failure(connection, sql)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() { bind(value, at: Int32(offset + 1), in: statement) }
        var rows: [SQLiteRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw failure(connection, sql) }
            rows.append(SQLiteRow(values: (0..<sqlite3_column_count(statement)).map { column(statement, $0) }))
        }
    }

    private func failure(_ connection: OpaquePointer, _ sql: String) -> Failure {
        Failure(
            code: sqlite3_errcode(connection) & 0xFF,
            error: .query(path: url.path, sql: sql, message: String(cString: sqlite3_errmsg(connection))))
    }

    /// SQLITE_TRANSIENT: SQLite copies the bytes, so Swift's temporary buffer may go away after the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ value: SQLiteValue, at index: Int32, in statement: OpaquePointer) {
        switch value {
        case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
        case .integer(let number): sqlite3_bind_int64(statement, index, number)
        case .real(let number): sqlite3_bind_double(statement, index, number)
        case .null: sqlite3_bind_null(statement, index)
        }
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, index))
        case SQLITE_NULL: return .null
        default:
            // A text or blob column: SQLite returns a NUL-terminated UTF-8 copy valid until the next step.
            guard let bytes = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: bytes))
        }
    }
}
