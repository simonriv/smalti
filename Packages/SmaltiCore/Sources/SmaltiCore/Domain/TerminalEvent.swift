/// Something that happened inside a pane's terminal, in domain terms.
public enum TerminalEvent: Equatable, Sendable {
    case titleChanged(String)
    case workingDirectoryChanged(WorkingDirectory)
    /// End of a shell command (OSC 133). `exitCode` is nil when the shell did not report one.
    case commandFinished(exitCode: Int?, duration: Duration)
    case bell
    /// The process in the foreground of the pane's terminal changed (e.g. `claude`, `vim`).
    case foregroundProcessChanged(ForegroundProcess)
    /// The terminal asked to close its pane.
    case closeRequested
    case exited(code: Int?)
}

public struct CommandOutcome: Equatable, Sendable {
    public let exitCode: Int?
    public let duration: Duration

    public init(exitCode: Int?, duration: Duration) {
        self.exitCode = exitCode
        self.duration = duration
    }
}

/// The program in the foreground of a pane, with its arguments when the engine could read them (to relaunch it).
public struct ForegroundProcess: Equatable, Sendable {
    public let name: String
    public let commandLine: [String]?

    public init(name: String, commandLine: [String]? = nil) {
        self.name = name
        self.commandLine = commandLine
    }
}
