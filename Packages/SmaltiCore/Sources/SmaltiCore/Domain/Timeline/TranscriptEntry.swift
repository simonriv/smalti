import Foundation

/// Whose transcript an entry comes from: the session's own, or one of its subagents'.
public enum EntryScope: Hashable, Sendable {
    case main
    case subagent(String)
}

/// One thing a transcript line says, in the timeline's words (spec F9, section 1). Adapters translate their lines
/// into these; the domain folds them into turns.
public struct TranscriptEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case prompt(ExcerptText)
        case reply(ExcerptText)
        case toolCall(ToolCallEntry)
        case toolResult(ToolResultEntry)
        case image(ImageNote)
        case compaction(CompactionNote)
        /// The subagent `agentID` was launched by the call `toolID` (Claude's `.meta.json` or `agentId:`).
        case subagentLink(agentID: String, toolID: String)
    }

    public let kind: Kind
    public let scope: EntryScope
    public let at: Date?

    public init(kind: Kind, scope: EntryScope, at: Date?) {
        self.kind = kind
        self.scope = scope
        self.at = at
    }
}

public struct ToolCallEntry: Equatable, Sendable {
    public let id: String
    public let name: String
    /// The text arguments, for the one-line summary (`command`, `file_path`…).
    public let arguments: [String: String]
    /// The whole call as the transcript has it (JSON), to show and copy.
    public let call: ExcerptText

    public init(id: String, name: String, arguments: [String: String], call: ExcerptText) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.call = call
    }
}

public struct ToolResultEntry: Equatable, Sendable {
    public let id: String
    public let isError: Bool
    public let exitCode: Int?
    public let diff: DiffStat?
    public let output: ExcerptText

    public init(id: String, isError: Bool, exitCode: Int?, diff: DiffStat?, output: ExcerptText) {
        self.id = id
        self.isError = isError
        self.exitCode = exitCode
        self.diff = diff
        self.output = output
    }
}

/// An image in a prompt or a result: noted, not painted (spec F9).
public struct ImageNote: Equatable, Sendable {
    public let mediaType: String
    public let byteCount: Int
    public let location: TextLocation

    public init(mediaType: String, byteCount: Int, location: TextLocation) {
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.location = location
    }
}

/// A compaction; Codex does not say how many tokens.
public struct CompactionNote: Equatable, Sendable {
    public let preTokens: Int?
    public let postTokens: Int?
    public let location: TextLocation

    public init(preTokens: Int?, postTokens: Int?, location: TextLocation) {
        self.preTokens = preTokens
        self.postTokens = postTokens
        self.location = location
    }
}
