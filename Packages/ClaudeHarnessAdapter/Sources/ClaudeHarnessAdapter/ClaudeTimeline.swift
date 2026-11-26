import Foundation
import JSONLReader
import SmaltiCore

/// Claude Code's transcripts for the timeline (spec F9): `projects/<folder>/<session>.jsonl` and its subagents in
/// `<session>/subagents/agent-<id>.jsonl` (with `.meta.json` naming the call that launched each). Reads only what
/// was added since the cursor, only in reading mode, and watches files only while someone listens.
public struct ClaudeTimeline: SessionTranscripts, ProjectTranscripts {
    public let harness = HarnessID.claude
    private let projectsRoot: URL
    private static let coalescing = Duration.milliseconds(150)

    public init(projectsRoot: URL) {
        self.projectsRoot = projectsRoot
    }

    private var list: ClaudeSessionList { ClaudeSessionList(root: projectsRoot, harness: harness) }

    // MARK: - SessionTranscripts

    public func locate(sessionID: String) async throws(TranscriptReadError) -> TranscriptSessionRef {
        let folders =
            (try? FileManager.default.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)) ?? []
        guard let folder = folders.first(where: { Self.exists($0.appending(path: "\(sessionID).jsonl")) }) else {
            throw .missing(path: projectsRoot.appending(path: "*/\(sessionID).jsonl").path(percentEncoded: false))
        }
        return Self.ref(sessionID, in: folder)
    }

    public func read(_ session: TranscriptSessionRef, from cursor: TranscriptCursor) async throws(TranscriptReadError)
        -> TranscriptRead
    {
        let files = [(URL(filePath: session.file), EntryScope.main)] + subagentFiles(of: session)
        guard Self.exists(files[0].0) else { throw .missing(path: session.file) }
        let restarted = files.contains { Self.wasRewritten($0.0, cursor) }
        var next = restarted ? TranscriptCursor.start : cursor
        var entries: [TranscriptEntry] = []
        for (file, scope) in files {
            entries += read(file, scope: scope, cursor: &next)
        }
        return TranscriptRead(entries: entries, cursor: next, restarted: restarted)
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
            let text = ClaudeTimelineTranslator.text(of: record, block: location.block, field: location.field)
        else { throw .unreadable(path: location.file, reason: "line \(location.offset) changed") }
        return text
    }

    public func changes(of session: TranscriptSessionRef) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let watch = SessionWatch(
                session: session, coalescing: Self.coalescing, subagents: { subagentFiles(of: session).map(\.0) },
                onChange: { continuation.yield() })
            continuation.onTermination = { _ in watch.cancel() }
        }
    }

    // MARK: - ProjectTranscripts

    public func sessions(under root: String, limit: Int) async throws(TranscriptReadError) -> [HarnessSession] {
        try located(under: root, limit: limit).map(\.session)
    }

    public func search(_ query: TimelineQuery, under root: String) -> AsyncThrowingStream<TranscriptHit, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for (session, file) in try located(under: root, limit: .max) {
                        guard !Task.isCancelled else { break }
                        let ref = Self.ref(session.id, in: file.deletingLastPathComponent())
                        for hit in try scan(ref, session: session, needle: query.needle) { continuation.yield(hit) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Files

    private static func exists(_ file: URL) -> Bool {
        FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
    }

    private static func ref(_ sessionID: String, in folder: URL) -> TranscriptSessionRef {
        TranscriptSessionRef(
            harness: .claude, sessionID: sessionID,
            file: folder.appending(path: "\(sessionID).jsonl").path(percentEncoded: false),
            subagentFolder: folder.appending(path: "\(sessionID)/subagents").path(percentEncoded: false))
    }

    private func located(under root: String, limit: Int) throws(TranscriptReadError) -> [(
        session: HarnessSession, file: URL
    )] {
        do {
            return try list.sessions(under: root, limit: limit)
        } catch .storeMissing {
            return []
        } catch {
            throw .unreadable(path: projectsRoot.path(percentEncoded: false), reason: String(describing: error))
        }
    }

    /// `agent-<id>.jsonl` files, by name, each with its scope.
    private func subagentFiles(of session: TranscriptSessionRef) -> [(URL, EntryScope)] {
        guard let folder = session.subagentFolder else { return [] }
        let files =
            (try? FileManager.default.contentsOfDirectory(at: URL(filePath: folder), includingPropertiesForKeys: nil))
            ?? []
        return files.filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0, .subagent(String($0.deletingPathExtension().lastPathComponent.dropFirst("agent-".count)))) }
    }

    private static func wasRewritten(_ file: URL, _ cursor: TranscriptCursor) -> Bool {
        let path = file.path(percentEncoded: false)
        guard let known = cursor.inodes[path], let identity = JSONLFileIdentity.of(file) else { return false }
        return identity.inode != known || identity.size < (cursor.offsets[path] ?? 0)
    }

    private func read(_ file: URL, scope: EntryScope, cursor: inout TranscriptCursor) -> [TranscriptEntry] {
        let path = file.path(percentEncoded: false)
        guard let identity = JSONLFileIdentity.of(file) else { return [] }
        let offset = cursor.offsets[path] ?? 0
        let translator = ClaudeTimelineTranslator(file: path, inode: identity.inode, scope: scope)
        var entries: [TranscriptEntry] = []
        if offset == 0, case .subagent(let agent) = scope, let link = Self.link(agent, next: file) {
            entries.append(TranscriptEntry(kind: link, scope: scope, at: nil))
        }
        let outcome = JSONLLineReader.read(file, from: offset) { line, at in
            autoreleasepool { entries += translator.translate(line, at: at).map(\.entry) }
        }
        cursor.offsets[path] = outcome.offset
        cursor.inodes[path] = identity.inode
        return entries
    }

    /// `.meta.json`'s `toolUseId`: the call that launched the subagent.
    private static func link(_ agent: String, next file: URL) -> TranscriptEntry.Kind? {
        let meta = file.deletingPathExtension().appendingPathExtension("meta.json")
        guard let data = try? Data(contentsOf: meta),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let tool = object["toolUseId"] as? String
        else { return nil }
        return .subagentLink(agentID: agent, toolID: tool)
    }

    private func scan(_ ref: TranscriptSessionRef, session: HarnessSession, needle: [UInt8]) throws -> [TranscriptHit] {
        var hits: [TranscriptHit] = []
        for (file, scope) in [(URL(filePath: ref.file), EntryScope.main)] + subagentFiles(of: ref) {
            guard let identity = JSONLFileIdentity.of(file) else { continue }
            let translator = ClaudeTimelineTranslator(
                file: file.path(percentEncoded: false), inode: identity.inode, scope: scope)
            try JSONLScanner.lines(containing: needle, in: file, isCancelled: { Task.isCancelled }) { line, at in
                autoreleasepool {
                    for item in translator.translate(line, at: at) {
                        guard let text = item.text else { continue }
                        hits.append(TranscriptHit(session: session, entry: item.entry, text: text))
                    }
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

/// The files of one session under watch: the main transcript, the subagents' folder and each subagent's transcript,
/// including those born while watching (the folder tells when one appears).
private final class SessionWatch: @unchecked Sendable {
    // Unchecked: `watches` and `isCancelled` are only touched under `lock`.
    private let lock = NSLock()
    private var watches: [String: FileWatch] = [:]
    private var isCancelled = false
    private let coalescing: Duration
    private let subagents: @Sendable () -> [URL]
    private let onChange: @Sendable () -> Void

    init(
        session: TranscriptSessionRef, coalescing: Duration, subagents: @escaping @Sendable () -> [URL],
        onChange: @escaping @Sendable () -> Void
    ) {
        self.coalescing = coalescing
        self.subagents = subagents
        self.onChange = onChange
        watch(URL(filePath: session.file), then: onChange)
        if let folder = session.subagentFolder {
            watch(URL(filePath: folder)) { [weak self] in
                self?.watchNewSubagents()
                onChange()
            }
        }
        watchNewSubagents()
    }

    private func watchNewSubagents() {
        for file in subagents() { watch(file, then: onChange) }
    }

    private func watch(_ file: URL, then action: @escaping @Sendable () -> Void) {
        let path = file.path(percentEncoded: false)
        lock.withLock {
            guard !isCancelled, watches[path] == nil else { return }
            watches[path] = try? FileWatch(file: file, coalescing: coalescing, onChange: action)
        }
    }

    func cancel() {
        let current = lock.withLock {
            isCancelled = true
            defer { watches = [:] }
            return Array(watches.values)
        }
        current.forEach { $0.cancel() }
    }
}
