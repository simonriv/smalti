/// What a pane runs when it opens.
public enum TerminalCommand: Hashable, Sendable {
    case loginShell
    case custom(String)
}

public struct TerminalSessionSpec: Hashable, Sendable {
    public let workingDirectory: WorkingDirectory
    public let command: TerminalCommand
    public let environment: [String: String]

    public init(workingDirectory: WorkingDirectory, command: TerminalCommand, environment: [String: String] = [:]) {
        self.workingDirectory = workingDirectory
        self.command = command
        self.environment = environment
    }

    public static func loginShell(in directory: WorkingDirectory) -> TerminalSessionSpec {
        TerminalSessionSpec(workingDirectory: directory, command: .loginShell)
    }
}
