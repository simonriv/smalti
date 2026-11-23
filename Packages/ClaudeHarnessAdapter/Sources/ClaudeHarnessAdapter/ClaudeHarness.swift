import SmaltiCore

/// Claude Code as a harness: resumes a session with `claude --resume <id>`.
public struct ClaudeHarness: HarnessAdapter {
    public let harness = HarnessID.claude
    private static let safeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    public init() {}

    public func resumeCommand(for agent: AgentSnapshot) -> String {
        "claude --resume \(Self.quoted(agent.sessionID))"
    }

    /// Session ids are UUIDs; anything else is single-quoted for the shell.
    private static func quoted(_ text: String) -> String {
        guard text.isEmpty || !text.allSatisfy(safeCharacters.contains) else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
