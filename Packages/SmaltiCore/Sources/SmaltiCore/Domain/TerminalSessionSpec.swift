/// What a pane runs when it opens.
public enum TerminalCommand: Hashable, Sendable {
    case loginShell
    case custom(String)
}

import Foundation

/// What a restored pane brings back before its shell starts.
public struct PaneRestoration: Hashable, Sendable {
    /// Printed before the shell, for panes that were at their shell.
    public let scrollback: Scrollback?
    /// Load the pane's own history on top of the shared one.
    public let restoresHistory: Bool
    /// When it was saved, for the "restaurado" banner.
    public let savedAt: Date

    public init(scrollback: Scrollback?, restoresHistory: Bool, savedAt: Date) {
        self.scrollback = scrollback
        self.restoresHistory = restoresHistory
        self.savedAt = savedAt
    }
}

public struct TerminalSessionSpec: Hashable, Sendable {
    public let workingDirectory: WorkingDirectory
    public let command: TerminalCommand
    public let environment: [String: String]
    public let restoration: PaneRestoration?
    /// Typed into the shell once it starts (e.g. `claude --resume 7f3a\n`).
    public let initialInput: String?

    public init(
        workingDirectory: WorkingDirectory, command: TerminalCommand, environment: [String: String] = [:],
        restoration: PaneRestoration? = nil, initialInput: String? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.command = command
        self.environment = environment
        self.restoration = restoration
        self.initialInput = initialInput
    }

    public static func loginShell(in directory: WorkingDirectory) -> TerminalSessionSpec {
        TerminalSessionSpec(workingDirectory: directory, command: .loginShell)
    }
}
