import Foundation
import SmaltiCore

/// OpenCode as a harness: resumes with `opencode -s <id>`, lists `session_v2` of its database (spec F6).
public struct OpenCodeHarness: HarnessAdapter {
    public let harness = HarnessID.opencode
    private let store: OpenCodeStore

    public init(database: URL) {
        self.store = OpenCodeStore(database: database)
    }

    /// `<data home>/opencode/opencode.db`; another channel's `opencode-<channel>.db` only when it is the one there.
    public static func defaultDatabase(dataHome: URL) -> URL {
        let folder = dataHome.appending(path: "opencode")
        let main = folder.appending(path: "opencode.db")
        guard !FileManager.default.fileExists(atPath: main.path) else { return main }
        let others = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("opencode-") && $0.hasSuffix(".db") }
        return others.count == 1 ? folder.appending(path: others[0]) : main
    }

    public func detect(_ process: ForegroundProcess) -> Bool { ProcessNames.matches(process, ["opencode"]) }

    public func listSessions(_ query: SessionQuery) async throws(HarnessError) -> [HarnessSession] {
        let sessions = try store.rows().map {
            HarnessSession(
                harness: harness, id: $0.id, directory: $0.directory, title: $0.title, createdAt: $0.createdAt,
                updatedAt: $0.updatedAt, detail: $0.model)
        }
        return SessionCatalog.merge([.success(sessions)], query: query).sessions
    }

    public func resumeCommand(sessionID: String) -> String {
        "opencode -s \(ShellWord.quoted(sessionID))"
    }

    public func continueCommand() -> String { "opencode -c" }

    /// OpenCode 2.x has no fork.
    public func forkCommand(sessionID: String) -> String? { nil }

    public func sessionID(fromCommandLine arguments: [String]) -> String? {
        guard let first = arguments.first, detect(ForegroundProcess(name: first)) else { return nil }
        return ProcessNames.value(after: ["-s", "--session"], in: arguments)
    }
}

/// OpenCode's token use for the Observatory: input counts cache reads, like Claude's (spec F6).
public struct OpenCodeUsage: HarnessUsage {
    /// Providers whose models run on this Mac. The database does not keep the provider's base URL (amendment 1).
    static let localProviders: Set<String> = ["ollama", "lmstudio"]

    private let store: OpenCodeStore

    public init(database: URL) {
        self.store = OpenCodeStore(database: database)
    }

    public func sessions(since: Date) async throws(HarnessError) -> [UsageRow] {
        try store.rows(updatedSince: since).map {
            UsageRow(
                harness: .opencode, sessionID: $0.id, directory: $0.directory, model: $0.model,
                isLocal: $0.provider.map(Self.localProviders.contains) ?? false, input: $0.input, output: $0.output,
                startedAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
    }
}
