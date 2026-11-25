import Foundation
import SmaltiCore

/// What the observatory already read, kept in `<estado>/observatory/index.json` so a restart reads only new lines.
struct TranscriptIndex: Codable {
    struct FileEntry: Codable, Equatable {
        var inode: UInt64
        var size: UInt64
        var offset: UInt64
        var modified: Date
        let sessionID: String
        let isSubagent: Bool
        var derivedFrom: [String] = []

        /// A file read again from the start names its sources again: they are kept once.
        static func merging(_ known: [String], _ new: [String]) -> [String] {
            known
                + new.filter { !known.contains($0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        }
    }

    static let formatVersion = 1

    var version = formatVersion
    var files: [String: FileEntry] = [:]
    var sessions: [String: SessionActivity] = [:]
    var owners = MessageOwners()

    /// The stored index, or an empty one when it is missing, unreadable or of another format version.
    static func load(from file: URL) -> TranscriptIndex {
        guard let data = try? Data(contentsOf: file),
            let index = try? JSONDecoder().decode(TranscriptIndex.self, from: data), index.version == formatVersion
        else { return TranscriptIndex() }
        return index
    }

    /// Written to a temporary file and renamed, so a half-written index never replaces a good one. F7.6: an index
    /// from a newer Smalti is left as it is, so two versions do not keep rebuilding each other's. Returns whether it
    /// wrote.
    @discardableResult
    func save(to file: URL) throws -> Bool {
        if let stored = Self.storedVersion(at: file),
            FormatCompatibility.of(stored: stored, current: Self.formatVersion).isNewer
        {
            return false
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
        return true
    }

    private struct StoredVersion: Decodable {
        let version: Int?
    }

    private static func storedVersion(at file: URL) -> Int? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONDecoder().decode(StoredVersion.self, from: data))?.version
    }

    /// Drops what was folded from `session`, so all its files are read again from the start.
    mutating func reset(_ session: String) {
        sessions[session] = nil
        owners.release(session)
        for (path, entry) in files where entry.sessionID == session {
            files[path]?.offset = 0
        }
    }
}
