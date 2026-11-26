import Foundation
import SmaltiCore

/// Hands out queued reads per session (one per call), counts live change streams and lets a test announce changes.
public actor FakeSessionTranscripts: SessionTranscripts {
    public nonisolated let harness: HarnessID
    private var refs: [String: TranscriptSessionRef] = [:]
    private var reads: [TranscriptSessionRef: [[TranscriptEntry]]] = [:]
    private var restarts: [TranscriptSessionRef: Int] = [:]
    private var delays: [TranscriptSessionRef: Duration] = [:]
    private var failures: [String: TranscriptReadError] = [:]
    private var readFailures: [TranscriptSessionRef: TranscriptReadError] = [:]
    /// Reads cut short because their task was cancelled.
    public private(set) var cancelledReads = 0
    private var texts: [TextLocation: String] = [:]
    private var cursors: [TranscriptSessionRef: [UInt64]] = [:]
    private var streams: [TranscriptSessionRef: [UUID: AsyncStream<Void>.Continuation]] = [:]
    /// Streams that ended before their registration ran (both hop onto this actor in no fixed order).
    private var ended: Set<UUID> = []

    public init(harness: HarnessID) {
        self.harness = harness
    }

    /// `restartAt`: the read (by number, from 0) that says the file was rewritten.
    public func add(_ ref: TranscriptSessionRef, reads: [[TranscriptEntry]], restartAt: Int? = nil) {
        refs[ref.sessionID] = ref
        self.reads[ref] = reads
        restarts[ref] = restartAt
    }

    public func slowDown(_ ref: TranscriptSessionRef, _ delay: Duration) { delays[ref] = delay }
    public func fail(_ sessionID: String, with error: TranscriptReadError) { failures[sessionID] = error }
    /// The next reads of `ref` throw `error`.
    public func failReads(_ ref: TranscriptSessionRef, with error: TranscriptReadError) { readFailures[ref] = error }
    public func setFullText(_ text: String, at location: TextLocation) { texts[location] = text }
    /// The cursor offsets each read started from, in order.
    public func cursorsRead(_ ref: TranscriptSessionRef) -> [UInt64] { cursors[ref] ?? [] }
    public var watchers: Int { streams.values.reduce(0) { $0 + $1.count } }

    public func change(_ ref: TranscriptSessionRef) {
        for continuation in streams[ref]?.values ?? [:].values { continuation.yield() }
    }

    public func locate(sessionID: String) async throws(TranscriptReadError) -> TranscriptSessionRef {
        if let failure = failures[sessionID] { throw failure }
        guard let ref = refs[sessionID] else { throw .missing(path: sessionID) }
        return ref
    }

    public func read(_ session: TranscriptSessionRef, from cursor: TranscriptCursor) async throws(TranscriptReadError)
        -> TranscriptRead
    {
        if let delay = delays[session], (try? await Task.sleep(for: delay)) == nil { cancelledReads += 1 }
        if let failure = readFailures[session] { throw failure }
        let index = Int(cursor.offsets[session.file] ?? 0)
        cursors[session, default: []].append(UInt64(index))
        let queued = reads[session] ?? []
        let entries = index < queued.count ? queued[index] : []
        var next = cursor
        next.offsets[session.file] = UInt64(min(index + 1, queued.count))
        return TranscriptRead(entries: entries, cursor: next, restarted: restarts[session] == index)
    }

    public func fullText(at location: TextLocation) async throws(TranscriptReadError) -> String {
        guard let text = texts[location] else { throw .missing(path: location.file) }
        return text
    }

    public nonisolated func changes(of session: TranscriptSessionRef) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let id = UUID()
        Task { await self.register(continuation, id: id, for: session) }
        continuation.onTermination = { _ in Task { await self.unregister(id, for: session) } }
        return stream
    }

    private func register(_ continuation: AsyncStream<Void>.Continuation, id: UUID, for session: TranscriptSessionRef) {
        guard ended.remove(id) == nil else { return }
        streams[session, default: [:]][id] = continuation
    }

    private func unregister(_ id: UUID, for session: TranscriptSessionRef) {
        guard streams[session]?[id] != nil else {
            ended.insert(id)
            return
        }
        streams[session]?[id] = nil
        if streams[session]?.isEmpty == true { streams[session] = nil }
    }
}

/// A project's sessions and the hits a search yields, in order.
public actor FakeProjectTranscripts: ProjectTranscripts {
    public nonisolated let harness: HarnessID
    private let sessions: [HarnessSession]
    private let hits: [TranscriptHit]
    private var delay = Duration.zero
    public private(set) var lastRoot: String?
    public private(set) var lastQuery: TimelineQuery?
    public private(set) var searches = 0

    public init(harness: HarnessID, sessions: [HarnessSession] = [], hits: [TranscriptHit] = []) {
        self.harness = harness
        self.sessions = sessions
        self.hits = hits
    }

    /// Each hit takes this long to come.
    public func slowDown(_ delay: Duration) { self.delay = delay }

    public func sessions(under root: String, limit: Int) async throws(TranscriptReadError) -> [HarnessSession] {
        lastRoot = root
        return Array(sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    public nonisolated func search(_ query: TimelineQuery, under root: String) -> AsyncThrowingStream<
        TranscriptHit, any Error
    > {
        AsyncThrowingStream { continuation in
            let task = Task {
                for hit in await self.started(query, root) {
                    if let delay = await self.delayed, delay > .zero { try? await Task.sleep(for: delay) }
                    guard !Task.isCancelled else { break }
                    continuation.yield(hit)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var delayed: Duration? { delay }

    private func started(_ query: TimelineQuery, _ root: String) -> [TranscriptHit] {
        searches += 1
        lastQuery = query
        lastRoot = root
        return hits
    }
}
