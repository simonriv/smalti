import Foundation
import SmaltiCore

/// Smalti's command history as JSON lines: one `HistoryEntry` per line, appended as each command ends.
///
/// The file and its folder are owner-only. Loading skips a half-written last line (no trailing newline) and any
/// unreadable line, counting the latter. When the file holds more than 20 % over `limit` lines, loading rewrites it
/// atomically with the last `limit`, so it never grows without bound.
public actor FileCommandHistory: CommandHistory {
    static let compactionMargin = 1.2

    private let file: URL
    private let limit: Int
    /// Lines that were not valid entries in the last load.
    public private(set) var skippedLines = 0

    public init(file: URL, limit: Int) {
        self.file = file
        self.limit = limit
    }

    public func load() async throws(HistoryError) -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw failure("load", error)
        }
        let lines = Self.completeLines(of: data)
        let entries = decode(lines)
        if Double(lines.count) > Double(limit) * Self.compactionMargin { try compact(keeping: entries.suffix(limit)) }
        return Array(entries.suffix(limit))
    }

    public func append(_ entry: HistoryEntry) async throws(HistoryError) {
        do {
            var line = try JSONEncoder().encode(entry)
            line.append(UInt8(ascii: "\n"))
            try prepareFile()
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            throw failure("append", error)
        }
    }

    private var path: String { file.path(percentEncoded: false) }

    private func prepareFile() throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard !FileManager.default.fileExists(atPath: path) else { return }
        guard FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: path]) }
    }

    private func decode(_ lines: [Data]) -> [HistoryEntry] {
        let decoder = JSONDecoder()
        var entries: [HistoryEntry] = []
        skippedLines = 0
        for line in lines where !line.isEmpty {
            if let entry = try? decoder.decode(HistoryEntry.self, from: line) {
                entries.append(entry)
            } else {
                skippedLines += 1
            }
        }
        return entries
    }

    private func compact(keeping entries: ArraySlice<HistoryEntry>) throws(HistoryError) {
        let encoder = JSONEncoder()
        var data = Data()
        do {
            for entry in entries {
                data.append(try encoder.encode(entry))
                data.append(UInt8(ascii: "\n"))
            }
        } catch {
            throw failure("compact", error)
        }
        do {
            try AtomicFile.write(data, to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch let error as SessionArchiveFailure {
            throw failure("compact", error.cause)
        } catch {
            throw failure("compact", error)
        }
    }

    /// The lines that end with a newline; a last line without one was cut while being written.
    private static func completeLines(of data: Data) -> [Data] {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { Data($0) }
        lines.removeLast()
        return lines
    }

    private func failure(_ operation: String, _ error: any Error) -> HistoryError {
        HistoryError(operation: operation, file: path, cause: String(describing: error))
    }
}
