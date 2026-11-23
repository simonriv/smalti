import Foundation

/// A terminal pane as the domain sees it: identity plus what its terminal has reported.
public struct Pane: Equatable, Sendable {
    public let id: PaneID
    public private(set) var title: String?
    public private(set) var workingDirectory: WorkingDirectory
    public private(set) var lastCommand: CommandOutcome?
    public private(set) var isRunning: Bool
    public private(set) var processName: String?
    public private(set) var foregroundCommandLine: [String]?
    /// Shell commands finished in this pane (OSC 133), shown when offering to restore it.
    public private(set) var commandCount = 0
    /// The coding agent running in this pane, if any.
    public private(set) var agent: AgentSession?

    public init(id: PaneID, workingDirectory: WorkingDirectory) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.isRunning = true
    }

    /// What the pane header shows: the foreground process, else the title.
    public var headerName: String { processName ?? title ?? "" }

    /// The shell itself is in the foreground (or nothing else was ever reported).
    public var isAtShell: Bool { processName.map(ShellNames.contains) ?? true }

    /// An agent event: starts the agent if the event names a session, then applies it.
    public func applying(_ event: AgentEvent) -> (Pane, AttentionReason?) {
        if event.isCompaction, agent != nil { return (self, nil) }
        let current = event.hook == .sessionStart ? restarted(from: event) : agent ?? AgentSession.start(from: event)
        guard let current else { return (self, nil) }
        let transition = current.applying(event)
        return (attaching(transition.session), transition.attention)
    }

    /// A terminal event, plus what it means for the agent when the agent did not say so itself.
    public func applying(_ event: TerminalEvent, at date: Date) -> Pane {
        let wasRunningAProgram = !isAtShell
        let updated = applying(event)
        guard let session = updated.agent, session.state.isActive else { return updated }
        switch event {
        case .commandFinished(let exitCode, _): return updated.attaching(session.ended(exitCode: exitCode, at: date))
        // Only a return from a program (Claude) to the shell; the shell starting before a resumed Claude is not.
        case .foregroundProcessChanged(let process) where wasRunningAProgram && ShellNames.contains(process.name):
            return updated.attaching(session.leftForTheShell())
        default: return updated
        }
    }

    /// A new `SessionStart` (e.g. after `--resume`) replaces the agent; the same session keeps its title.
    private func restarted(from event: AgentEvent) -> AgentSession? {
        guard let fresh = AgentSession.start(from: event) else { return nil }
        guard let previous = agent, previous.sessionID == fresh.sessionID, let title = previous.title else {
            return fresh
        }
        return AgentSession(
            harness: fresh.harness, sessionID: fresh.sessionID, title: title, state: fresh.state,
            startedAt: previous.startedAt)
    }

    public func attaching(_ session: AgentSession?) -> Pane {
        var updated = self
        updated.agent = session
        return updated
    }

    public func applying(_ event: TerminalEvent) -> Pane {
        var updated = self
        switch event {
        case .titleChanged(let title): updated.title = title
        case .workingDirectoryChanged(let directory): updated.workingDirectory = directory
        case .commandFinished(let exitCode, let duration):
            updated.lastCommand = CommandOutcome(exitCode: exitCode, duration: duration)
            updated.commandCount += 1
        case .exited: updated.isRunning = false
        case .foregroundProcessChanged(let process):
            updated.processName = process.name
            updated.foregroundCommandLine = process.commandLine
        case .bell, .closeRequested, .searchTotal, .searchSelected, .linkHovered, .secureInputRequested: break
        }
        return updated
    }
}
