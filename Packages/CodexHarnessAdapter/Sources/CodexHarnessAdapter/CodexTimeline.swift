import Foundation
import JSONLReader
import SQLiteReader
import SmaltiCore

/// Codex's rollouts for the timeline (spec F9): found through `state_5.sqlite` (`threads.rollout_path`), read
/// incrementally and only for reading. Rollouts compressed to `.zst` cannot be read on macOS.
public struct CodexTimeline: SessionTranscripts, ProjectTranscripts {
    public let harness = HarnessID.codex
    private let home: URL
    private static let coalescing = Duration.milliseconds(150)
    private static let sessionsFolder = "/sessions/"

    /// `home` is `$CODEX_HOME` (by default `~/.codex`), resolved by the composition root.
    public init(home: URL) {
        self.home = home
    }

    private struct Thread {
        let session: HarnessSession
        let rollout: String
    }

    // MARK: - SessionTranscripts

    public func locate(sessionID: String) async throws(TranscriptReadError) -> TranscriptSessionRef {
        guard let thread = try threads("id = ?", [.text(sessionID)], limit: 1).first else {
            throw .missing(path: home.appending(path: "sessions/**/*\(sessionID).jsonl").path(percentEncoded: false))
        }
        guard !thread.rollout.hasSuffix(".zst") else { throw .compressed(path: thread.rollout) }
        return TranscriptSessionRef(harness: harness, sessionID: sessionID, file: thread.rollout, subagentFolder: nil)
    }

    public func read(_ session: TranscriptSessionRef, from cursor: TranscriptCursor) async throws(TranscriptReadError)
        -> TranscriptRead
    {
        let file = URL(filePath: session.file)
        guard let identity = JSONLFileIdentity.of(file) else { throw .missing(path: session.file) }
        let rewritten =
            cursor.inodes[session.file].map { $0 != identity.inode } ?? false
            || identity.size < (cursor.offsets[session.file] ?? 0)
        var next = rewritten ? TranscriptCursor.start : cursor
        let translator = CodexTimelineTranslator(file: session.file, inode: identity.inode)
        var entries: [TranscriptEntry] = []
        let outcome = JSONLLineReader.read(
            file, from: next.offsets[session.file] ?? 0, isCancelled: { Task.isCancelled }
        ) {
            line, at in
            autoreleasepool { entries += translator.translate(line, at: at).map(\.entry) }
        }
        if let failure = outcome.failure { throw .unreadable(path: session.file, reason: String(describing: failure)) }
        next.offsets[session.file] = outcome.offset
        next.inodes[session.file] = identity.inode
        return TranscriptRead(entries: entries, cursor: next, restarted: rewritten)
    }

    public func fullText(at location: TextLocation) async throws(TranscriptReadError) -> String {
        let file = URL(filePath: location.file)
        guard JSONLFileIdentity.of(file)?.inode == location.inode else { throw .missing(path: location.file) }
        let line: Data
        do {
            line = try JSONLLineAt.line(in: file, at: location.offset, length: location.length)
        } catch {
            throw Self.translated(error)
        }
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
            let text = CodexTimelineTranslator.text(of: record, field: location.field)
        else { throw .unreadable(path: location.file, reason: "line \(location.offset) changed") }
        return text
    }

    public func changes(of session: TranscriptSessionRef) -> AsyncStream<Void> {
        let file = URL(filePath: session.file)
        return AsyncStream { continuation in
            let watch = try? FileWatch(file: file, coalescing: Self.coalescing) { continuation.yield() }
            continuation.onTermination = { _ in watch?.cancel() }
        }
    }

    // MARK: - ProjectTranscripts

    public func sessions(under root: String, limit: Int) async throws(TranscriptReadError) -> [HarnessSession] {
        try threads(under: root, limit: limit).map(\.session)
    }

    public func search(_ query: TimelineQuery, under root: String) -> AsyncThrowingStream<TranscriptHit, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for thread in try threads(under: root, limit: .max) where !thread.rollout.hasSuffix(".zst") {
                        guard !Task.isCancelled else { break }
                        for hit in try scan(thread, needle: query.needle) { continuation.yield(hit) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Index

    private var store: URL { home.appending(path: "state_5.sqlite") }

    private func threads(under root: String, limit: Int) throws(TranscriptReadError) -> [Thread] {
        let trimmed = root.hasSuffix("/") && root.count > 1 ? String(root.dropLast()) : root
        return try threads(
            "(cwd = ? or substr(cwd, 1, ?) = ?)",
            [.text(trimmed), .integer(Int64(trimmed.utf8.count + 1)), .text(trimmed + "/")], limit: limit)
    }

    private func threads(_ condition: String, _ bindings: [SQLiteValue], limit: Int) throws(TranscriptReadError)
        -> [Thread]
    {
        guard FileManager.default.fileExists(atPath: store.path(percentEncoded: false)) else { return [] }
        let rows: [SQLiteRow]
        do {
            rows = try SQLiteReader(url: store).rows(
                "select id, cwd, title, created_at, updated_at, rollout_path from threads where archived = 0 and "
                    + "\(condition) order by updated_at desc limit \(min(limit, Int(Int32.max)))", bindings)
        } catch {
            throw .unreadable(path: store.path(percentEncoded: false), reason: String(describing: error))
        }
        return rows.compactMap(thread)
    }

    private func thread(_ row: SQLiteRow) -> Thread? {
        guard let id = row[text: 0], let directory = row[text: 1], let created = row[integer: 3],
            let updated = row[integer: 4], let rollout = row[text: 5]
        else { return nil }
        return Thread(
            session: HarnessSession(
                harness: harness, id: id, directory: directory, title: row[text: 2] ?? "",
                createdAt: Date(timeIntervalSince1970: TimeInterval(created)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(updated)), detail: nil),
            rollout: resolved(rollout))
    }

    /// The rollout under this home's `sessions` when it is there (a copied or moved `CODEX_HOME` keeps the old
    /// absolute path in its index), else the path the index stores.
    private func resolved(_ rollout: String) -> String {
        guard let range = rollout.range(of: Self.sessionsFolder) else { return rollout }
        let local = home.appending(path: "sessions").appending(path: String(rollout[range.upperBound...]))
            .path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: local) ? local : rollout
    }

    private func scan(_ thread: Thread, needle: [UInt8]) throws -> [TranscriptHit] {
        let file = URL(filePath: thread.rollout)
        guard let identity = JSONLFileIdentity.of(file) else { return [] }
        let translator = CodexTimelineTranslator(file: thread.rollout, inode: identity.inode)
        var hits: [TranscriptHit] = []
        try JSONLScanner.lines(containing: needle, in: file, isCancelled: { Task.isCancelled }) { line, at in
            autoreleasepool {
                for item in translator.translate(line, at: at) {
                    guard let text = item.text else { continue }
                    hits.append(TranscriptHit(session: thread.session, entry: item.entry, text: text))
                }
            }
        }
        return hits
    }

    private static func translated(_ error: JSONLReadError) -> TranscriptReadError {
        switch error {
        case .missing(let path): .missing(path: path)
        case .unreadable(let path, let reason): .unreadable(path: path, reason: reason)
        }
    }
}
