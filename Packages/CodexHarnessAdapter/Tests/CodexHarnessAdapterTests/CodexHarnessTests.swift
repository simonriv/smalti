import CodexHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Codex's fixture: two `codex exec` sessions recorded with Ollama (`qwen3:4b`), one per work directory (plan T1).
enum CodexFixture {
    static var description: HarnessFixtureDescription {
        get throws {
            let source = try #require(Bundle.module.url(forResource: "Fixtures/codex", withExtension: nil))
            return HarnessFixtureDescription(
                harness: .codex, source: source, processName: "codex", resume: { "codex resume \($0)" },
                continueCommand: "codex resume --last", fork: { "codex fork \($0)" },
                commandLine: { ["codex", "resume", $0] })
        }
    }

    static func harness(home: URL) -> CodexHarness { CodexHarness(home: home.appending(path: "codex")) }

    /// Runs SQL against a copied fixture store with the system's sqlite3 (only tests write).
    static func sql(_ statement: String, in home: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [home.appending(path: "codex/state_5.sqlite").path, statement]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "sqlite3 \(statement)")
    }
}

@Suite("CodexHarness", .serialized)
struct CodexHarnessTests {
    @Test func codexSatisfiesTheHarnessContract() async throws {
        try await HarnessAdapterContract.verify(
            fixture: try CodexFixture.description, make: CodexFixture.harness,
            breakSchema: { try CodexFixture.sql("alter table threads rename column cwd to folder", in: $0) })
    }

    @Test func detailNamesProviderAndTokens() async throws {
        let home = try FixtureHome.materialize(try CodexFixture.description)

        let sessions = try await CodexFixture.harness(home: home).listSessions(SessionQuery())

        #expect(sessions.allSatisfy { $0.detail?.hasPrefix("ollama · ") == true })
        #expect(sessions.allSatisfy { $0.detail?.hasSuffix(" tokens") == true })
    }

    @Test func archivedThreadsAreNotListed() async throws {
        let home = try FixtureHome.materialize(try CodexFixture.description)
        let expected = try FixtureExpectations.load(from: try CodexFixture.description.source)
        let archived = try #require(expected.sessions.first?.id)
        try CodexFixture.sql("update threads set archived = 1 where id = '\(archived)'", in: home)

        let sessions = try await CodexFixture.harness(home: home).listSessions(SessionQuery())

        #expect(!sessions.map(\.id).contains(archived))
        #expect(sessions.count == expected.sessions.count - 1)
    }

    @Test func subagentAndNonInteractiveThreadsAreNotListed() async throws {
        let home = try FixtureHome.materialize(try CodexFixture.description)
        let ids = try FixtureExpectations.load(from: try CodexFixture.description.source).sessions.map(\.id)
        try CodexFixture.sql(
            "update threads set attached_thread_parent_id = '\(ids[1])' where id = '\(ids[0])'", in: home)
        try CodexFixture.sql("update threads set source = 'mcp' where id = '\(ids[1])'", in: home)

        #expect(try await CodexFixture.harness(home: home).listSessions(SessionQuery()).isEmpty)
    }

    @Test func interactiveSourcesAreListed() async throws {
        let home = try FixtureHome.materialize(try CodexFixture.description)
        try CodexFixture.sql("update threads set source = 'cli'", in: home)

        #expect(try await CodexFixture.harness(home: home).listSessions(SessionQuery()).count == 2)
    }

    @Test func missingStateDbIsStoreMissing() async throws {
        let home = try FixtureHome.materialize(try CodexFixture.description)
        try FileManager.default.removeItem(at: home.appending(path: "codex/state_5.sqlite"))

        await #expect(throws: HarnessError.self) {
            try await CodexFixture.harness(home: home).listSessions(SessionQuery())
        }
    }

    @Test func readsResumeAndForkCommandLines() {
        let codex = CodexHarness(home: URL(filePath: "/private/tmp/smalti-fx/none"))

        #expect(codex.sessionID(fromCommandLine: ["codex", "resume", "0198"]) == "0198")
        #expect(codex.sessionID(fromCommandLine: ["codex", "resume", "--last"]) == nil)
        #expect(codex.sessionID(fromCommandLine: ["codex", "fork", "0198"]) == nil)
        #expect(codex.sessionID(fromCommandLine: ["/opt/homebrew/bin/codex", "resume", "0198"]) == "0198")
    }
}
