import Foundation

/// One model reply as a transcript line reports it. Claude Code writes a reply once per content block, all with
/// the same `messageID` and usage: folding counts each id once.
public struct AssistantTurn: Equatable, Sendable {
    public let messageID: String
    public let model: ModelID
    public let usage: TokenUsage
    public let at: Date
    /// A subagent's reply: its tokens belong to the session, but not its model, context or chart.
    public let isSubagent: Bool

    public init(messageID: String, model: ModelID, usage: TokenUsage, at: Date, isSubagent: Bool) {
        self.messageID = messageID
        self.model = model
        self.usage = usage
        self.at = at
        self.isSubagent = isSubagent
    }
}

public struct ToolStart: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// The tool's text arguments (`command`, `file_path`, `pattern`…); others are left out.
    public let input: [String: String]
    public let at: Date
    public let isSubagent: Bool

    public init(id: String, name: String, input: [String: String], at: Date, isSubagent: Bool = false) {
        self.id = id
        self.name = name
        self.input = input
        self.at = at
        self.isSubagent = isSubagent
    }
}

/// Lines added and removed by an edit, from its result's patch.
public struct DiffStat: Codable, Equatable, Sendable {
    public let added: Int
    public let removed: Int

    public init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }
}

public struct ToolFinish: Equatable, Sendable {
    public let id: String
    public let isError: Bool
    public let exitCode: Int?
    public let diff: DiffStat?
    public let at: Date
    public let isSubagent: Bool

    public init(id: String, isError: Bool, exitCode: Int?, diff: DiffStat?, at: Date, isSubagent: Bool = false) {
        self.id = id
        self.isError = isError
        self.exitCode = exitCode
        self.diff = diff
        self.at = at
        self.isSubagent = isSubagent
    }
}

public struct Compaction: Codable, Equatable, Sendable {
    public let at: Date
    public let preTokens: Int
    public let postTokens: Int

    public init(at: Date, preTokens: Int, postTokens: Int) {
        self.at = at
        self.preTokens = preTokens
        self.postTokens = postTokens
    }
}

/// What the observatory takes from one transcript line; the adapter translates, the domain folds.
public enum TranscriptRecord: Equatable, Sendable {
    case assistantTurn(AssistantTurn)
    case toolStarted(ToolStart)
    case toolFinished(ToolFinish)
    case compacted(Compaction)
    case sessionInfo(sessionID: String, cwd: String, at: Date)
}
