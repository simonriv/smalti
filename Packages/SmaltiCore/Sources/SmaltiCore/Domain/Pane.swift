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
        case .bell, .closeRequested: break
        }
        return updated
    }
}
