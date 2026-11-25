import Foundation
import SmaltiCore

/// Claude Code as a harness: resumes with `claude --resume <id>` and lists the transcripts under
/// `~/.claude/projects/<directory>/<id>.jsonl`. The session id normally comes from its `SessionStart` hook (F2); the
/// listing also feeds the search and the capture of a Claude without Smalti's plugin.
public struct ClaudeHarness: HarnessAdapter, EditorConnectable {
    public let harness = HarnessID.claude
    private let projectsRoot: URL

    /// `projectsRoot` is `<CLAUDE_CONFIG_DIR or ~/.claude>/projects`, resolved by the composition root.
    public init(projectsRoot: URL) {
        self.projectsRoot = projectsRoot
    }

    public func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, ["claude"]) }

    public func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] {
        let sessions = try ClaudeSessionList(root: projectsRoot, harness: harness).sessions()
        return SessionCatalog.merge([.success(sessions)], query: query).sessions
    }

    public func resumeCommand(for agent: AgentSnapshot) -> String {
        "claude --resume \(ShellWord.quoted(agent.sessionID ?? ""))"
    }

    public func resumeCommandConnectingEditor(for agent: AgentSnapshot) -> String {
        resumeCommand(for: agent) + " --ide"
    }

    public func continueCommand() -> String { "claude --continue" }

    public func forkCommand(for agent: AgentSnapshot) -> String? {
        resumeCommand(for: agent) + " --fork-session"
    }

    public func sessionID(fromCommandLine arguments: [String]) -> String? {
        guard let first = arguments.first, detect(ForegroundProcess(name: first)) else { return nil }
        return ProcessNames.value(after: ["--resume", "-r"], in: arguments)
    }
}
