import Foundation

/// A coding-agent session running in a pane, as its hooks report it.
public struct AgentSession: Equatable, Sendable {
    public let harness: HarnessID
    public let sessionID: String
    public private(set) var title: String?
    public private(set) var state: AgentState
    public let startedAt: Date

    public init(harness: HarnessID, sessionID: String, title: String?, state: AgentState, startedAt: Date) {
        self.harness = harness
        self.sessionID = sessionID
        self.title = title
        self.state = state
        self.startedAt = startedAt
    }

    /// Characters of the first prompt kept as the session's title.
    public static let titleLength = 80

    /// A new session from an event that names one (Claude Code includes it in every hook); nil without an id.
    public static func start(from event: AgentEvent) -> AgentSession? {
        guard let id = event.sessionID, !id.isEmpty else { return nil }
        return AgentSession(
            harness: .claude, sessionID: id, title: nil, state: .waiting(since: event.at, reason: .turnFinished),
            startedAt: event.at)
    }

    /// The state after `event` (spec F2, transition table) and whether it calls for the user's attention.
    public func applying(_ event: AgentEvent) -> AgentTransition {
        var next = self
        switch event.hook {
        case .sessionStart:
            next.state = .waiting(since: event.at, reason: .turnFinished)
        case .userPromptSubmit:
            next.state = .working
            if next.title == nil { next.title = event.prompt.flatMap(Self.title(from:)) }
        case .preToolUse, .postToolUse:
            // Final review: a subagent's tools in the same pane never hide an approval that still waits.
            if case .waiting(_, .approval) = state { return AgentTransition(session: self, attention: nil) }
            next.state = .working
        case .permissionRequest:
            let summary = event.toolSummary ?? ""
            next.state = .waiting(since: event.at, reason: .permission(summary))
            return AgentTransition(session: next, attention: .permission(summary))
        case .notification:
            return notified(event)
        case .stop:
            next.state = .waiting(since: event.at, reason: .turnFinished)
            return AgentTransition(session: next, attention: .turnFinished)
        case .stopFailure:
            let message = event.message ?? ""
            next.state = .failed(since: event.at, message: message)
            return AgentTransition(session: next, attention: .failure(message))
        case .sessionEnd:
            next.state = .stopped
        }
        return AgentTransition(session: next, attention: nil)
    }

    /// F7.5: Smalti holds one of its commands until the user approves it.
    public func awaitingApproval(_ subject: ApprovalSubject, at date: Date) -> AgentTransition {
        var next = self
        next.state = .waiting(since: date, reason: .approval(subject.summary))
        let attention = AttentionReason.approval(
            command: subject.shortCommand, environment: subject.environment.label)
        return AgentTransition(session: next, attention: attention)
    }

    /// Nothing waits for approval any more: the agent goes on. Any other wait stays.
    public func approvalSettled() -> AgentSession {
        guard case .waiting(_, .approval) = state else { return self }
        var next = self
        next.state = .working
        return next
    }

    /// A notification while already waiting (Claude's 60 s idle reminder after a stop, or the one that comes with a
    /// permission request) or failed changes nothing: the user was already told, and a reminder is no recovery.
    private func notified(_ event: AgentEvent) -> AgentTransition {
        switch state {
        case .waiting, .failed: return AgentTransition(session: self, attention: nil)
        case .working, .stopped: break
        }
        var next = self
        let message = event.message ?? ""
        next.state = .waiting(since: event.at, reason: .attention(message))
        return AgentTransition(session: next, attention: .attention(message))
    }

    /// The process ended on its own (no `SessionEnd`): failed with a non-zero code, else stopped.
    func ended(exitCode: Int?, at date: Date) -> AgentSession {
        var next = self
        if let code = exitCode, code != 0 {
            next.state = .failed(since: date, message: "salió con código \(code)")
        } else {
            next.state = .stopped
        }
        return next
    }

    /// Back at the shell without an exit report: stopped, unless it already failed.
    func leftForTheShell() -> AgentSession {
        guard state.isActive else { return self }
        var next = self
        next.state = .stopped
        return next
    }

    private static func title(from prompt: String) -> String? {
        let firstLine = prompt.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(titleLength))
    }

    public var snapshot: AgentSnapshot {
        AgentSnapshot(harness: harness, sessionID: sessionID, title: title, lastState: state.kind)
    }
}
