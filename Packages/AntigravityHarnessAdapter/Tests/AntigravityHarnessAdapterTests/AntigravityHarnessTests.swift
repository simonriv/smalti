import AntigravityHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Antigravity's fixture: two `agy -p` sessions recorded with Simón's account, one per work directory (plan T1).
enum AntigravityFixture {
    static let conversations = ".gemini/antigravity-cli/conversations"

    static var description: HarnessFixtureDescription {
        get throws {
            let source = try #require(Bundle.module.url(forResource: "Fixtures/antigravity", withExtension: nil))
            return HarnessFixtureDescription(
                harness: .antigravity, source: source, processName: "antigravity",
                resume: { "agy --conversation \($0)" }, continueCommand: "agy -c", fork: nil,
                commandLine: { ["/opt/homebrew/Caskroom/antigravity-cli/1.5.10/antigravity", "--conversation", $0] },
                createdFile: { "\(conversations)/\($0).db" })
        }
    }

    static func harness(home: URL) -> AntigravityHarness {
        AntigravityHarness(root: home.appending(path: ".gemini/antigravity-cli"))
    }

    static func sql(_ statement: String, in home: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [
            home.appending(path: ".gemini/antigravity-cli/conversation_summaries.db").path, statement,
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "sqlite3 \(statement)")
    }
}

@Suite("AntigravityHarness", .serialized)
struct AntigravityHarnessTests {
    @Test func antigravitySatisfiesTheHarnessContract() async throws {
        try await HarnessAdapterContract.verify(
            fixture: try AntigravityFixture.description, make: AntigravityFixture.harness,
            breakSchema: {
                try AntigravityFixture.sql(
                    "alter table conversation_summaries rename column workspace_uris to folders", in: $0)
            })
    }

    @Test func malformedWorkspaceUrisOmitsRow() async throws {
        let home = try FixtureHome.materialize(try AntigravityFixture.description)
        let expected = try FixtureExpectations.load(from: try AntigravityFixture.description.source)
        let broken = try #require(expected.sessions.first?.id)
        try AntigravityFixture.sql(
            "update conversation_summaries set workspace_uris = '[not json' where conversation_id = '\(broken)'",
            in: home)

        let sessions = try await AntigravityFixture.harness(home: home).listSessions(SessionQuery())

        #expect(sessions.map(\.id) == expected.sessions.dropFirst().map(\.id))
    }

    @Test func percentEncodedUriDecodes() async throws {
        let home = try FixtureHome.materialize(try AntigravityFixture.description)
        let expected = try FixtureExpectations.load(from: try AntigravityFixture.description.source)
        let id = try #require(expected.sessions.first?.id)
        try AntigravityFixture.sql(
            "update conversation_summaries set workspace_uris = '[\"file:///tmp/dir%20con%20%C3%B1\"]' "
                + "where conversation_id = '\(id)'", in: home)

        let sessions = try await AntigravityFixture.harness(home: home).listSessions(SessionQuery())

        #expect(sessions.first { $0.id == id }?.directory == "/tmp/dir con ñ")
    }

    @Test func missingConversationFileFallsBackToModifiedTime() async throws {
        let home = try FixtureHome.materialize(try AntigravityFixture.description)
        let expected = try FixtureExpectations.load(from: try AntigravityFixture.description.source)
        let id = try #require(expected.sessions.first?.id)
        try FileManager.default.removeItem(at: home.appending(path: "\(AntigravityFixture.conversations)/\(id).db"))

        let sessions = try await AntigravityFixture.harness(home: home).listSessions(SessionQuery())
        let session = try #require(sessions.first { $0.id == id })

        #expect(session.createdAt == session.updatedAt)
    }

    @Test func parsesSummaryTimestamps() {
        let date = AntigravityHarness.timestamp("2026-11-25 02:58:49.003794+00:00")
        let offset = AntigravityHarness.timestamp("2026-11-24T21:58:49-05:00")

        #expect(date.map { abs($0.timeIntervalSince1970 - 1_795_575_529.003794) < 0.001 } == true)
        #expect(offset.map { abs($0.timeIntervalSince1970 - 1_795_575_529) < 0.001 } == true)
        #expect(AntigravityHarness.timestamp("ayer") == nil)
    }
}
