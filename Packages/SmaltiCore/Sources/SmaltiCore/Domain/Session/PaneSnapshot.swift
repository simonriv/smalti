import Foundation

/// The agent of a pane as saved, enough to resume it with its harness.
public struct AgentSnapshot: Codable, Equatable, Sendable {
    public let harness: HarnessID
    /// Nil when no session was captured: the pane continues the directory's last one (spec F6).
    public let sessionID: String?
    public let title: String?
    /// Nil for a harness without hooks (no state is known).
    public let lastState: AgentStateKind?

    public init(harness: HarnessID, sessionID: String?, title: String?, lastState: AgentStateKind?) {
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

    /// Arguments with control characters cannot be typed into the shell safely (a newline would run a second
    /// command), so such a command line is never offered for relaunch.
    static func isTypeable(_ arguments: [String]) -> Bool {
        !arguments.contains { $0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
    }

    private static func quoted(_ argument: String) -> String {
        // zsh expands a word starting with `=` to a command path, so it is quoted too.
        let isPlain = !argument.isEmpty && !argument.hasPrefix("=") && argument.allSatisfy(safeCharacters.contains)
        guard !isPlain else { return argument }
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
    /// F6: what a Smalti Neovim pane showed.
    public let editor: EditorPosition?

    public init(
        id: UUID, workingDirectory: String, title: String?, processName: String?, scrollbackLines: Int,
        commandCount: Int, relaunch: RelaunchCommand?, agent: AgentSnapshot?, editor: EditorPosition? = nil
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.title = title
        self.processName = processName
        self.scrollbackLines = scrollbackLines
        self.commandCount = commandCount
        self.relaunch = relaunch
        self.agent = agent
        self.editor = editor
    }

    public init(_ pane: Pane, scrollbackLines: Int, editor: EditorPosition? = nil) {
        id = pane.id.rawValue
        workingDirectory = pane.workingDirectory.path
        title = pane.title
        processName = pane.processName
        self.scrollbackLines = scrollbackLines
        commandCount = pane.commandCount
        // A finished agent whose pane is back at its shell is a shell again: it restores with its scrollback.
        // A harness without hooks counts while its own process is in the foreground (F6); a finished agent of another
        // harness that ran here before gives way to it (final review I1).
        let harness = pane.liveHarnessBinding
        let agent = pane.agent.flatMap { agent in
            let isReplaced = harness.map { $0.harness != agent.harness } == true && !agent.state.isActive
            return (agent.state.isActive || !pane.isAtShell) && !isReplaced ? agent : nil
        }
        self.agent =
            agent?.snapshot
            ?? harness.map { AgentSnapshot(harness: $0.harness, sessionID: $0.sessionID, title: nil, lastState: nil) }
        self.editor = editor
        let canRelaunch = !pane.isAtShell && self.agent == nil && editor == nil
        let commandLine = pane.foregroundCommandLine.flatMap { RelaunchCommand.isTypeable($0) ? $0 : nil }
        relaunch = canRelaunch ? commandLine.map(RelaunchCommand.init(arguments:)) : nil
    }
}
