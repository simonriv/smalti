import Foundation
import SQLite3
import SQLiteReader
import Testing

/// A writable connection for the tests, made with the C API (only the tests write).
final class Writer {
    private var db: OpaquePointer?

    init(_ url: URL, wal: Bool = false) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        if wal { try run("pragma journal_mode=wal") }
    }

    func run(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(
                .fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    deinit { sqlite3_close(db) }
}

@Suite("SQLiteReader")
struct SQLiteReaderTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "sqlite-reader-\(UUID())")

    private func database(_ name: String = "store.db", wal: Bool = false) throws -> (URL, Writer) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        let writer = try Writer(url, wal: wal)
        try writer.run("create table threads (id text, cwd text, n integer, r real)")
        try writer.run("insert into threads values ('a', '/w/a', 1, 0.5), ('b', null, 2, 1.5)")
        return (url, writer)
    }

    @Test func readsRowsWithBindings() throws {
        let (url, _) = try database()

        let rows = try SQLiteReader(url: url).rows("select id, cwd, n, r from threads where n >= ?", [.integer(2)])

        #expect(rows.count == 1)
        #expect(rows[0][text: 0] == "b")
        #expect(rows[0][text: 1] == nil)
        #expect(rows[0][integer: 2] == 2)
        #expect(rows[0][real: 3] == 1.5)
    }

    @Test func listsColumns() throws {
        let (url, _) = try database()

        #expect(try SQLiteReader(url: url).columns(of: "threads") == ["id", "cwd", "n", "r"])
        #expect(try SQLiteReader(url: url).columns(of: "missing").isEmpty)
    }

    @Test func missingFileIsOpenError() {
        let reader = SQLiteReader(url: folder.appending(path: "nope.db"))

        #expect(throws: SQLiteReadError.self) { try reader.rows("select 1") }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "nope.db").path))
    }

    @Test func badQueryIsQueryError() throws {
        let (url, _) = try database()

        do {
            _ = try SQLiteReader(url: url).rows("select nope from threads")
            Issue.record("expected an error")
        } catch {
            guard case .query(let path, _, let message) = error else {
                Issue.record("\(error)")
                return
            }
            #expect(path == url.path)
            #expect(message.contains("nope"))
        }
    }

    @Test func readsWhileWriterHoldsWAL() throws {
        let (url, writer) = try database(wal: true)
        try writer.run("insert into threads values ('c', '/w/c', 3, 0)")
        try writer.run("begin immediate; insert into threads values ('d', '/w/d', 4, 0)")

        let ids = try SQLiteReader(url: url).rows("select id from threads order by id").map { $0[text: 0] }

        #expect(ids == ["a", "b", "c"])
        try writer.run("commit")
    }

    @Test func lockedDatabaseIsTypedErrorWithoutHanging() throws {
        let (url, writer) = try database()
        try writer.run("begin exclusive; insert into threads values ('x', '/w/x', 9, 0)")
        let started = Date()

        #expect(throws: SQLiteReadError.self) { try SQLiteReader(url: url).rows("select id from threads") }
        #expect(Date().timeIntervalSince(started) < 2)
        try writer.run("commit")
    }

    @Test func directoryWithoutWritePermissionStillReads() throws {
        let (url, writer) = try database(wal: true)
        try writer.run("pragma wal_checkpoint(truncate)")
        withExtendedLifetime(writer) {}
        try? FileManager.default.removeItem(at: URL(filePath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(filePath: url.path + "-wal"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        #expect(try SQLiteReader(url: url).rows("select id from threads").count == 2)
    }

    @Test func unicodeAndSpacesInPath() throws {
        let (url, _) = try database("dir con espacio ñ #?.db")

        #expect(try SQLiteReader(url: url).rows("select id from threads").count == 2)
    }

    @Test func neverWritesTheStore() throws {
        let (url, _) = try database()
        let before = try Data(contentsOf: url)

        _ = try SQLiteReader(url: url).rows("select id from threads")

        #expect(try Data(contentsOf: url) == before)
    }
}
