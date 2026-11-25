import Foundation
import SQLiteReader
import SmaltiCore

/// Codex as a harness. Its sessions are rollouts under `$CODEX_HOME/sessions/…` (compressed to `.zst` after a week),
/// indexed in `state_5.sqlite`, table `threads`: the listing reads only the index (spec F6).
public struct CodexHarness: HarnessAdapter {
    static let requiredColumns = ["id", "cwd", "title", "created_at", "updated_at", "archived"]

    public let harness = HarnessID.codex
    private let home: URL

    /// `home` is `$CODEX_HOME` (by default `~/.codex`), resolved by the composition root.
    public init(home: URL) {
        self.home = home
    }

    private var store: URL { home.appending(path: "state_5.sqlite") }

    public func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, ["codex"]) }

    public func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] {
        guard FileManager.default.fileExists(atPath: store.path) else {
            throw .storeMissing(harness: harness, path: store.path)
        }
        let reader = SQLiteReader(url: store)
        do {
            let columns = try reader.columns(of: "threads")
            if let missing = Self.requiredColumns.first(where: { !columns.contains($0) }) {
                throw HarnessError.unknownSchema(harness: harness, path: store.path, missing: missing)
            }
            let extras = ["model_provider", "tokens_used"].map { columns.contains($0) ? $0 : "null" }
            let rows = try reader.rows(
                "select id, cwd, title, created_at, updated_at, \(extras.joined(separator: ", ")) from threads "
                    + "where archived = 0 order by updated_at desc")
            return SessionCatalog.merge([.success(rows.compactMap(session))], query: query).sessions
        } catch let error as HarnessError {
            throw error
        } catch {
            throw .unreadable(harness: harness, path: store.path, reason: String(describing: error))
        }
    }

    private func session(_ row: SQLiteRow) -> HarnessSession? {
        guard let id = row[text: 0], let directory = row[text: 1], let created = row[integer: 3],
            let updated = row[integer: 4]
        else { return nil }
        return HarnessSession(
            harness: harness, id: id, directory: directory, title: row[text: 2] ?? "",
            createdAt: Date(timeIntervalSince1970: TimeInterval(created)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(updated)),
            detail: Self.detail(provider: row[text: 5], tokens: row[integer: 6]))
    }

    /// "ollama · 4.439 tokens".
    static func detail(provider: String?, tokens: Int64?) -> String? {
        let parts = [provider, tokens.map { "\(ResumeListing.grouped(Int($0))) tokens" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public func resumeCommand(for agent: AgentSnapshot) -> String {
        "codex resume \(ShellWord.quoted(agent.sessionID ?? ""))"
    }

    public func continueCommand() -> String { "codex resume --last" }

    public func forkCommand(for agent: AgentSnapshot) -> String? {
        "codex fork \(ShellWord.quoted(agent.sessionID ?? ""))"
    }

    public func sessionID(fromCommandLine arguments: [String]) -> String? {
        guard let first = arguments.first, detect(ForegroundProcess(name: first)),
            arguments.dropFirst().first == "resume"
        else { return nil }
        return ProcessNames.value(after: ["resume"], in: arguments)
    }
}
