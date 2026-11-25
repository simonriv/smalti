import Foundation

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
    /// F4.5: matches of the pane's scrollback search; nil when no search is active.
    case searchTotal(Int?)
    /// F4.5: index of the selected search match; nil when none is selected.
    case searchSelected(Int?)
    /// F4.5: the link under the pointer while ⌘ is held; nil when the pointer leaves it.
    case linkHovered(String?)
    /// F4.5: the terminal asks for secure keyboard entry (a password prompt) or releases it.
    case secureInputRequested(Bool)
    /// F5.5: the word under the mouse pointer changed; nil when the pointer is over no word or left the pane.
    case pointerWordChanged(PointerWord?)
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
    /// F6: which process, and since when, so a harness's new session can be told from older ones.
    public let pid: Int32?
    public let startedAt: Date?

    public init(name: String, commandLine: [String]? = nil, pid: Int32? = nil, startedAt: Date? = nil) {
        self.name = name
        self.commandLine = commandLine
        self.pid = pid
        self.startedAt = startedAt
    }
}
