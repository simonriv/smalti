import Foundation

/// Port: one coding-agent CLI (Claude Code, Codex, Antigravity, OpenCode). Each adapter reads only its own store and
/// knows its own commands; the domain never switches on the harness (spec F6).
public protocol HarnessAdapter: Sendable {
    var harness: HarnessID { get }
    /// Shown in the interface ("Claude Code").
    var displayName: String { get }
    /// The pane's foreground process is this harness.
    func detect(_ process: ForegroundProcess) -> Bool
    /// The session a harness that just started in a pane is writing, if it is on disk already.
    func captureSessionId(in window: CaptureWindow) async throws(HarnessError) -> String?
    /// The sessions saved on disk that match `query`, newest first.
    func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession]
    /// The shell command that resumes `agent` (e.g. `codex resume 0198…`), on one line.
    func resumeCommand(sessionID: String) -> String
    /// The fallback when no id was captured: continue the directory's last session (`agy -c`).
    func continueCommand() -> String
    /// The command that forks `agent` into a new session; nil when the harness cannot fork.
    func forkCommand(sessionID: String) -> String?
    /// The session a command line resumes by name (`codex resume <id>`), so a resumed pane keeps its id.
    func sessionID(fromCommandLine arguments: [String]) -> String?
}

extension HarnessAdapter {
    public var displayName: String { harness.displayName }

    /// Capture from the listing: the first session created after the start that the window admits.
    public func captureSessionId(in window: CaptureWindow) async throws(HarnessError) -> String? {
        window.choose(try await listSessions(SessionQuery(directory: window.directory, limit: .max)))
    }
}

/// A harness that can connect to the editor (Claude with claudecode.nvim): restored with its editor flag when Smalti
/// knows an editor integration is installed (spec F6, `--ide`).
public protocol EditorConnectable {
    func resumeCommandConnectingEditor(sessionID: String) -> String
    func forkCommandConnectingEditor(sessionID: String) -> String
}

/// Process names compared by their last path component, so a wrapper or an absolute path still matches.
public enum ProcessNames {
    public static func matches(_ process: ForegroundProcess, _ names: Set<String>) -> Bool {
        let candidates = [process.name] + (process.commandLine?.first.map { [$0] } ?? [])
        return candidates.contains { names.contains(lastComponent($0)) }
    }

    /// The value after `flag` in `arguments` (`["codex", "resume", id]` with `["resume"]`).
    public static func value(after flags: Set<String>, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(where: flags.contains), arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1]
        return ShellWord.isSafeID(value) && !value.hasPrefix("-") ? value : nil
    }

    private static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// The known harness adapters, looked up by id or by the process they run as (no switch per harness). For a
/// repeated id the first one wins.
public struct HarnessRegistry: Sendable {
    private let adapters: [HarnessID: any HarnessAdapter]
    public let all: [any HarnessAdapter]

    public init(_ adapters: [any HarnessAdapter]) {
        self.adapters = Dictionary(adapters.map { ($0.harness, $0) }) { first, _ in first }
        var seen: Set<HarnessID> = []
        self.all = adapters.filter { seen.insert($0.harness).inserted }
    }

    public func adapter(for harness: HarnessID) -> (any HarnessAdapter)? { adapters[harness] }

    public func adapter(detecting process: ForegroundProcess) -> (any HarnessAdapter)? {
        all.first { $0.detect(process) }
    }
}
