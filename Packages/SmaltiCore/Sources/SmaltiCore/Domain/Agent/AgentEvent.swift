import Foundation

/// The Claude Code hooks Smalti listens to (spec F2, part C). F6 maps other harnesses onto the same events.
public enum AgentHook: String, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    /// After an approved permission, the tool starts: the agent works again.
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case sessionEnd = "SessionEnd"
}

/// Something an agent reported about itself, already translated from its hook payload.
public struct AgentEvent: Equatable, Sendable {
    public let pane: PaneID
    public let hook: AgentHook
    public let at: Date
    public let sessionID: String?
    public let prompt: String?
    /// What it asks permission for, summarised (`pnpm db:migrate`).
    public let toolSummary: String?
    public let message: String?
    /// Why a session started (`startup`, `resume`, `clear`, `compact`).
    public let source: String?

    public init(
        pane: PaneID, hook: AgentHook, at: Date, sessionID: String?, prompt: String? = nil, toolSummary: String? = nil,
        message: String? = nil, source: String? = nil
    ) {
        self.pane = pane
        self.hook = hook
        self.at = at
        self.sessionID = sessionID
        self.prompt = prompt
        self.toolSummary = toolSummary
        self.message = message
        self.source = source
    }

    /// A session start from compacting the context, mid-turn: it changes nothing about what the agent is doing.
    var isCompaction: Bool { hook == .sessionStart && source == "compact" }
}

/// Why the user should look at an agent now.
public enum AttentionReason: Equatable, Sendable {
    case permission(String)
    case attention(String)
    case turnFinished
    case failure(String)
}

public struct AgentTransition: Equatable, Sendable {
    public let session: AgentSession
    public let attention: AttentionReason?
}
