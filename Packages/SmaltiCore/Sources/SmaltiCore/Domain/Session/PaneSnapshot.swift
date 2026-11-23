import Foundation

/// The agent of a pane as saved, enough to resume it with its harness.
public struct AgentSnapshot: Codable, Equatable, Sendable {
    public let harness: HarnessID
    public let sessionID: String
    public let title: String?
    public let lastState: AgentStateKind

    public init(harness: HarnessID, sessionID: String, title: String?, lastState: AgentStateKind) {
        self.harness = harness
        self.sessionID = sessionID
        self.title = title
        self.lastState = lastState
    }
}

/// A foreground program to start again in a restored pane (e.g. `pnpm dev`).
public struct RelaunchCommand: Codable, Equatable, Sendable {
    public let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }

    /// The arguments quoted for a POSIX shell and joined with spaces, as typed into the shell and shown in the UI.
    public var displayText: String { arguments.map(Self.quoted).joined(separator: " ") }

    private static let safeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")

    private static func quoted(_ argument: String) -> String {
        guard argument.isEmpty || !argument.allSatisfy(safeCharacters.contains) else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// One pane of a saved workspace. `id` keeps the pane's identity across restarts (scrollback, history, hooks).
public struct PaneSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let workingDirectory: String
    public let title: String?
    public let processName: String?
    public let scrollbackLines: Int
    public let commandCount: Int
    public let relaunch: RelaunchCommand?
    public let agent: AgentSnapshot?

    public init(
        id: UUID, workingDirectory: String, title: String?, processName: String?, scrollbackLines: Int,
        commandCount: Int, relaunch: RelaunchCommand?, agent: AgentSnapshot?
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.title = title
        self.processName = processName
        self.scrollbackLines = scrollbackLines
        self.commandCount = commandCount
        self.relaunch = relaunch
        self.agent = agent
    }

    init(_ pane: Pane, scrollbackLines: Int) {
        id = pane.id.rawValue
        workingDirectory = pane.workingDirectory.path
        title = pane.title
        processName = pane.processName
        self.scrollbackLines = scrollbackLines
        commandCount = pane.commandCount
        agent = pane.agent?.snapshot
        let canRelaunch = !pane.isAtShell && pane.agent == nil
        relaunch = canRelaunch ? pane.foregroundCommandLine.map(RelaunchCommand.init(arguments:)) : nil
    }
}
