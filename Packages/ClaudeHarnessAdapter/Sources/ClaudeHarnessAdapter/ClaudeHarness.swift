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
        let sessions = try ClaudeSessionList(root: projectsRoot, harness: harness).sessions(newest: query.readLimit)
        return SessionCatalog.merge([.success(sessions)], query: query).sessions
    }

    /// Only the project folder of the pane's directory, and only transcripts born since the start (review 1, I2):
    /// the capture repeats every 2 s and must not read every transcript of the machine.
    public func captureSessionId(in window: CaptureWindow) async throws(HarnessError) -> String? {
        let list = ClaudeSessionList(root: projectsRoot, harness: harness)
        let born = window.processStartedAt.addingTimeInterval(-CaptureWindow.margin)
        return window.choose(try list.sessions(inProjectOf: window.directory, bornSince: born))
    }

    public func resumeCommand(sessionID: String) -> String {
        "claude --resume \(ShellWord.quoted(sessionID))"
    }

    public func resumeCommandConnectingEditor(sessionID: String) -> String {
        resumeCommand(sessionID: sessionID) + " --ide"
    }

    public func continueCommand() -> String { "claude --continue" }

    public func forkCommand(sessionID: String) -> String? {
        resumeCommand(sessionID: sessionID) + " --fork-session"
    }

    public func sessionID(fromCommandLine arguments: [String]) -> String? {
        guard let first = arguments.first, detect(ForegroundProcess(name: first)),
            !arguments.contains("--fork-session")
        else { return nil }
        return ProcessNames.value(after: ["--resume", "-r"], in: arguments)
    }
}
