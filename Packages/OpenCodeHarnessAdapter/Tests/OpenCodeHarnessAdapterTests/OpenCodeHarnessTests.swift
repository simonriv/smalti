import Foundation
import OpenCodeHarnessAdapter
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// OpenCode's fixture: two `opencode run` sessions recorded with Ollama (`qwen3:4b`), one per work directory.
enum OpenCodeFixture {
    static let database = ".local/share/opencode/opencode.db"

    static var description: HarnessFixtureDescription {
        get throws {
            let source = try #require(Bundle.module.url(forResource: "Fixtures/opencode", withExtension: nil))
            return HarnessFixtureDescription(
                harness: .opencode, source: source, processName: "opencode", resume: { "opencode -s \($0)" },
                continueCommand: "opencode -c", fork: nil, commandLine: { ["opencode", "-s", $0] })
        }
    }

    static func harness(home: URL) -> OpenCodeHarness { OpenCodeHarness(database: home.appending(path: database)) }

    static func sql(_ statement: String, in home: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [home.appending(path: database).path, statement]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "sqlite3 \(statement)")
    }
}

@Suite("OpenCodeHarness", .serialized)
struct OpenCodeHarnessTests {
    @Test func opencodeSatisfiesTheHarnessContract() async throws {
        try await HarnessAdapterContract.verify(
            fixture: try OpenCodeFixture.description, make: OpenCodeFixture.harness,
            breakSchema: { try OpenCodeFixture.sql("alter table session_v2 rename column directory to folder", in: $0) }
        )
    }

    @Test func detailNamesTheModel() async throws {
        let home = try FixtureHome.materialize(try OpenCodeFixture.description)

        let sessions = try await OpenCodeFixture.harness(home: home).listSessions(SessionQuery())

        #expect(sessions.allSatisfy { $0.detail == "qwen3:4b" })
    }

    @Test func childAndArchivedSessionsAreNotListed() async throws {
        let home = try FixtureHome.materialize(try OpenCodeFixture.description)
        let ids = try FixtureExpectations.load(from: try OpenCodeFixture.description.source).sessions.map(\.id)
        try OpenCodeFixture.sql("update session_v2 set parent_id = '\(ids[1])' where id = '\(ids[0])'", in: home)
        try OpenCodeFixture.sql("update session_v2 set time_archived = 1 where id = '\(ids[1])'", in: home)

        #expect(try await OpenCodeFixture.harness(home: home).listSessions(SessionQuery()).isEmpty)
    }

    @Test func malformedMessageJsonKeepsRowWithoutModel() async throws {
        let home = try FixtureHome.materialize(try OpenCodeFixture.description)
        try OpenCodeFixture.sql("update session_message set data = '{broken'", in: home)

        let sessions = try await OpenCodeFixture.harness(home: home).listSessions(SessionQuery())

        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.detail == nil })
    }

    @Test func oneXSchemaIsUnknownSchema() async throws {
        let home = try FixtureHome.materialize(try OpenCodeFixture.description)
        try OpenCodeFixture.sql("drop table session_v2; create table session (id text, directory text)", in: home)

        do {
            _ = try await OpenCodeFixture.harness(home: home).listSessions(SessionQuery())
            Issue.record("a 1.x database must be an unknown schema")
        } catch {
            #expect(
                error
                    == .unknownSchema(
                        harness: .opencode, path: home.appending(path: OpenCodeFixture.database).path,
                        missing: "session_v2"))
        }
    }

    @Test func defaultDatabasePrefersMainChannel() throws {
        let data = FileManager.default.temporaryDirectory.appending(path: "opencode-data-\(UUID())")
        let folder = data.appending(path: "opencode")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let home = try FixtureHome.materialize(try OpenCodeFixture.description)
        try FileManager.default.copyItem(
            at: home.appending(path: OpenCodeFixture.database), to: folder.appending(path: "opencode-beta.db"))

        #expect(OpenCodeHarness.defaultDatabase(dataHome: data).lastPathComponent == "opencode-beta.db")
        try FileManager.default.copyItem(
            at: home.appending(path: OpenCodeFixture.database), to: folder.appending(path: "opencode.db"))
        #expect(OpenCodeHarness.defaultDatabase(dataHome: data).lastPathComponent == "opencode.db")
    }

    @Test func readsSessionFlagsFromCommandLine() {
        let opencode = OpenCodeHarness(database: URL(filePath: "/private/tmp/smalti-fx/none.db"))

        #expect(opencode.sessionID(fromCommandLine: ["opencode", "--session", "ses_1"]) == "ses_1")
        #expect(opencode.sessionID(fromCommandLine: ["opencode", "-c"]) == nil)
    }
}

/// Nested in the serialized suite: both copy the fixture to the same fixed path.
extension OpenCodeHarnessTests {
    @Suite("OpenCodeUsage")
    struct OpenCodeUsageTests {
        private func usage() throws -> (OpenCodeUsage, URL) {
            let home = try FixtureHome.materialize(try OpenCodeFixture.description)
            return (OpenCodeUsage(database: home.appending(path: OpenCodeFixture.database)), home)
        }

        @Test func usageSumsCacheReadIntoInput() async throws {
            let (reader, home) = try usage()
            try OpenCodeFixture.sql(
                "update session_v2 set tokens_input = 100, tokens_cache_read = 20, tokens_output = 7", in: home)

            let rows = try await reader.sessions(since: .distantPast)

            #expect(rows.count == 2)
            #expect(rows.allSatisfy { $0.input == 120 && $0.output == 7 && $0.harness == .opencode })
            #expect(rows.allSatisfy { $0.cacheRead == 20 })
        }

        @Test func ollamaProviderIsLocal() async throws {
            let (reader, _) = try usage()

            let rows = try await reader.sessions(since: .distantPast)

            #expect(rows.allSatisfy { $0.isLocal && $0.model == "qwen3:4b" })
        }

        @Test func remoteProviderIsNotLocal() async throws {
            let (reader, home) = try usage()
            try OpenCodeFixture.sql(
                "update session_message set data = json_set(data, '$.model.providerID', 'anthropic') where type = 'assistant'",
                in: home)

            #expect(try await reader.sessions(since: .distantPast).allSatisfy { !$0.isLocal })
        }

        @Test func onlySessionsActiveSinceThePeriod() async throws {
            let (reader, _) = try usage()

            #expect(try await reader.sessions(since: Date().addingTimeInterval(60)).isEmpty)
        }
    }
}
