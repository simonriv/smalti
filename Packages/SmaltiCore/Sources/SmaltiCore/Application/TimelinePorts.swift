import Foundation

/// A session's transcript on disk: its main file and, for Claude, its subagents' folder.
public struct TranscriptSessionRef: Hashable, Sendable {
    public let harness: HarnessID
    public let sessionID: String
    public let file: String
    public let subagentFolder: String?

    public init(harness: HarnessID, sessionID: String, file: String, subagentFolder: String?) {
        self.harness = harness
        self.sessionID = sessionID
        self.file = file
        self.subagentFolder = subagentFolder
    }
}

/// Where the last read stopped, per file (offset and inode); `start` reads everything.
public struct TranscriptCursor: Equatable, Sendable {
    public var offsets: [String: UInt64]
    public var inodes: [String: UInt64]

    public init(offsets: [String: UInt64] = [:], inodes: [String: UInt64] = [:]) {
        self.offsets = offsets
        self.inodes = inodes
    }

    public static let start = TranscriptCursor()
}

/// What a read found: new entries and where to go on. `restarted` means a file was rewritten (another inode or a
/// smaller size): the entries are the whole session again and replace the timeline.
public struct TranscriptRead: Equatable, Sendable {
    public let entries: [TranscriptEntry]
    public let cursor: TranscriptCursor
    public let restarted: Bool

    public init(entries: [TranscriptEntry], cursor: TranscriptCursor, restarted: Bool) {
        self.entries = entries
        self.cursor = cursor
        self.restarted = restarted
    }
}

public enum TranscriptReadError: Error, Equatable, Sendable {
    case missing(path: String)
    case unreadable(path: String, reason: String)
    /// Codex compresses week-old rollouts with zstd, which macOS cannot read (spec F9).
    case compressed(path: String)

    public func message(_ texts: TimelineTexts) -> String {
        switch self {
        case .missing(let path): texts.missing(["path": path])
        case .unreadable(let path, let reason): texts.unreadable(["path": path, "reason": reason])
        case .compressed: texts.compressed
        }
    }
}

/// Port (F9): one harness's session transcripts, read incrementally and only while the timeline shows them.
public protocol SessionTranscripts: Sendable {
    var harness: HarnessID { get }
    func locate(sessionID: String) async throws(TranscriptReadError) -> TranscriptSessionRef
    func read(_ session: TranscriptSessionRef, from cursor: TranscriptCursor) async throws(TranscriptReadError)
        -> TranscriptRead
    /// The whole text at `location`, read again from the transcript.
    func fullText(at location: TextLocation) async throws(TranscriptReadError) -> String
    /// Tells when the session's files change. Watching stops when the consumer is cancelled.
    func changes(of session: TranscriptSessionRef) -> AsyncStream<Void>
}

/// Port (F9): one harness's sessions of a project (`root` and the folders under it), listed and searched on demand.
public protocol ProjectTranscripts: Sendable {
    var harness: HarnessID { get }
    /// The newest `limit` sessions, newest first.
    func sessions(under root: String, limit: Int) async throws(TranscriptReadError) -> [HarnessSession]
    /// Lines whose text may hold the query, newest session first; the domain confirms each.
    func search(_ query: TimelineQuery, under root: String) -> AsyncThrowingStream<TranscriptHit, any Error>
}

/// The transcript adapters by harness, as `HarnessRegistry` keeps the harness adapters.
public struct TranscriptSources: Sendable {
    private let sessions: [HarnessID: any SessionTranscripts]
    public let projects: [any ProjectTranscripts]

    public init(sessions: [any SessionTranscripts], projects: [any ProjectTranscripts]) {
        self.sessions = Dictionary(sessions.map { ($0.harness, $0) }) { first, _ in first }
        self.projects = projects
    }

    public func session(_ harness: HarnessID) -> (any SessionTranscripts)? { sessions[harness] }

    /// The harnesses whose transcripts the timeline can show.
    public var readable: Set<HarnessID> { Set(sessions.keys) }

    func project(_ harness: HarnessID) -> (any ProjectTranscripts)? {
        projects.first { $0.harness == harness }
    }

    /// The newest sessions of every harness under `root`, newest first; a harness that fails is left out.
    func recent(under root: String, limit: Int) async -> [HarnessSession] {
        var all: [HarnessSession] = []
        for project in projects {
            all += (try? await project.sessions(under: root, limit: limit)) ?? []
        }
        return Array(all.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }
}
