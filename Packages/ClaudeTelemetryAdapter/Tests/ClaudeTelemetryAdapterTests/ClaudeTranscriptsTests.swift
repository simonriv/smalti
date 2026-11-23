import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@testable import ClaudeTelemetryAdapter

@Suite("ClaudeTranscripts")
struct ClaudeTranscriptsTests {
    private let since = TranscriptHome.now.addingTimeInterval(-30 * 86_400)

    private func sessions(_ transcripts: ClaudeTranscripts) async throws -> [String: SessionActivity] {
        let activity = try await transcripts.activity(since: since)
        return Dictionary(uniqueKeysWithValues: activity.sessions.map { ($0.sessionID, $0) })
    }

    private struct Expected: Decodable {
        struct Totals: Decodable, Equatable {
            let input, output, cacheRead, cacheWrite5m, cacheWrite1h: Int
        }
        let sessions: [String: Totals]
        let total: Totals
    }

    private func totals(_ usage: TokenUsage) -> Expected.Totals {
        Expected.Totals(
            input: usage.input, output: usage.output, cacheRead: usage.cacheRead, cacheWrite5m: usage.cacheWrite5m,
            cacheWrite1h: usage.cacheWrite1h)
    }

    @Test func realFixturesMatchOracleExactly() async throws {
        let home = try TranscriptHome()
        try home.copyRealFixtures()
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: TranscriptHome.fixtures.appending(path: "real/expected.json")))

        let found = try await sessions(home.transcripts())

        #expect(Set(found.keys) == Set(expected.sessions.keys))
        for (id, totalsOfSession) in expected.sessions {
            #expect(found[id].map { totals($0.total) } == totalsOfSession, "session \(id)")
        }
        #expect(totals(found.values.map(\.total).reduce(.zero, +)) == expected.total)
    }

    @Test func growingFileCountsRepeatedMessageOnce() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1")])
        let transcripts = home.transcripts()
        _ = try await sessions(transcripts)

        try home.append(TranscriptHome.reply("m1") + "\n" + TranscriptHome.reply("m2") + "\n")

        #expect(try await sessions(transcripts)["s"]?.total.output == 200)
    }

    @Test func partialLastLineIsReadOnNextPass() async throws {
        let home = try TranscriptHome()
        try home.copySynthetic("partial-line.jsonl")
        let transcripts = home.transcripts()
        #expect(try await sessions(transcripts)["s"]?.total.output == 100)

        try home.append(
            String(contentsOf: TranscriptHome.fixtures.appending(path: "synthetic/partial-line.rest"), encoding: .utf8))

        #expect(try await sessions(transcripts)["s"]?.total.output == 107)
    }

    @Test func truncatedFileIsReread() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1"), TranscriptHome.reply("m2")])
        let transcripts = home.transcripts()
        _ = try await sessions(transcripts)

        try home.write([TranscriptHome.reply("m3", output: 5)])

        #expect(try await sessions(transcripts)["s"]?.total.output == 5)
    }

    @Test func replacedFileByInodeIsReread() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1")])
        let transcripts = home.transcripts()
        _ = try await sessions(transcripts)
        let replacement = home.root.appending(path: "replacement.jsonl")
        try Data((TranscriptHome.reply("m9", output: 1) + "\n" + TranscriptHome.reply("m8", output: 2) + "\n").utf8)
            .write(to: replacement)

        _ = try FileManager.default.replaceItemAt(home.file(session: "s"), withItemAt: replacement)

        #expect(try await sessions(transcripts)["s"]?.total.output == 3)
    }

    @Test func corruptIndexIsRebuilt() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1")])
        try FileManager.default.createDirectory(
            at: home.indexFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: home.indexFile)

        #expect(try await sessions(home.transcripts())["s"]?.total.output == 100)
    }

    @Test func malformedLineIsSkippedAndCounted() async throws {
        let home = try TranscriptHome()
        try home.copySynthetic("malformed.jsonl")
        let transcripts = home.transcripts()

        let found = try await sessions(transcripts)

        #expect(found["s"]?.total.output == 103)
        #expect(await transcripts.skippedLines == 1)
    }

    @Test func multiMegabyteLineIsRead() async throws {
        let home = try TranscriptHome()
        let huge = String(repeating: "x", count: 4 * 1_024 * 1_024)
        let toolResult =
            #"{"type":"user","timestamp":"2026-11-18T15:00:00Z","sessionId":"s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"\#(huge)"}]}}"#
        try home.write([toolResult, TranscriptHome.reply("m1", output: 9)])

        #expect(try await sessions(home.transcripts())["s"]?.total.output == 9)
    }

    @Test func compactionRecordIsTranslated() async throws {
        let home = try TranscriptHome()
        try home.copySynthetic("tools-and-compaction.jsonl")

        let session = try await sessions(home.transcripts())["s"]

        #expect(session?.lastCompaction?.preTokens == 967_809)
        #expect(session?.lastCompaction?.postTokens == 57_813)
        #expect(session?.cwd == "/fixture/work/x")
    }

    @Test func toolResultCarriesExitCodeAndDiff() async throws {
        let home = try TranscriptHome()
        try home.copySynthetic("tools-and-compaction.jsonl")

        let tools = try await sessions(home.transcripts())["s"]?.recentTools ?? []

        #expect(tools.map(\.summary) == ["reminder.service.ts +3 −2", "pnpm lint --fix"])
        #expect(tools.last?.outcome == .failed(exitCode: 1))
    }

    @Test func missingBreakdownCountsAsFiveMinuteWrite() async throws {
        let home = try TranscriptHome()
        try home.copySynthetic("no-breakdown.jsonl")

        let usage = try await sessions(home.transcripts())["s"]?.total

        #expect(usage?.cacheWrite5m == 40)
        #expect(usage?.cacheWrite1h == 0)
    }

    @Test func syntheticRepliesAreNotUsage() async throws {
        let home = try TranscriptHome()
        try home.copySynthetic("unknown-model.jsonl")

        let session = try await sessions(home.transcripts())["s"]

        #expect(session?.total.output == 11)
        #expect(session?.model == ModelID(rawValue: "claude-unknown-9"))
    }

    @Test func filesOlderThanThirtyDaysAreSkipped() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1")])
        try FileManager.default.setAttributes(
            [.modificationDate: TranscriptHome.now.addingTimeInterval(-31 * 86_400)],
            ofItemAtPath: home.file(session: "s").path(percentEncoded: false))

        #expect(try await sessions(home.transcripts()).isEmpty)
    }

    @Test func indexSurvivesRestartWithoutRereading() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1", output: 100)])
        _ = try await sessions(home.transcripts())
        // Same size and inode, different bytes: only a reader that starts over would see them.
        try home.write([TranscriptHome.reply("m1", output: 900)])

        #expect(try await sessions(home.transcripts())["s"]?.total.output == 100)
    }

    @Test func subagentTokensJoinTheirSession() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1")])
        try home.write(
            [TranscriptHome.reply("sub1", output: 7)], session: "agent-a", project: "-fixture-work-x/s/subagents")

        let found = try await sessions(home.transcripts())

        #expect(found["s"]?.total.output == 107)
        #expect(found.count == 1)
        #expect(found["s"]?.model == ModelID(rawValue: "claude-haiku-5-5"))
    }

    @Test func stepwiseIndexingReportsWhatIsComplete() async throws {
        let home = try TranscriptHome()
        for (index, age) in [1.0, 3, 10].enumerated() {
            try home.write([TranscriptHome.reply("m\(index)")], session: "s\(index)")
            try FileManager.default.setAttributes(
                [.modificationDate: TranscriptHome.now.addingTimeInterval(-age * 86_400)],
                ofItemAtPath: home.file(session: "s\(index)").path(percentEncoded: false))
        }
        let transcripts = home.transcripts(budget: .zero)

        let first = try await transcripts.activity(since: since)

        #expect(first.sessions.map(\.sessionID) == ["s0"])
        #expect(first.indexedSince > since)
        await AgentTranscriptsContract.verify(transcripts, since: since)
    }

    @Test func realFixturesHonourTheContract() async throws {
        let home = try TranscriptHome()
        try home.copyRealFixtures()

        await AgentTranscriptsContract.verify(home.transcripts(), since: since)
    }

    @Test func missingProjectsDirectoryIsEmptyNotAnError() async throws {
        let home = try TranscriptHome()
        try FileManager.default.removeItem(at: home.projects)

        #expect(try await sessions(home.transcripts()).isEmpty)
    }

    private func writeForkChain(_ home: TranscriptHome) throws {
        let derived = { (source: String) in
            #"{"type":"derived-from","sessionId":"x","sessions":[{"type":"claude_code_session","id":"\#(source)","via":"fork"}]}"#
        }
        try home.write([TranscriptHome.reply("s1", output: 1)], session: "s")
        try home.write(
            [derived("s"), TranscriptHome.reply("s1", output: 1), TranscriptHome.reply("f1", output: 10)], session: "f1"
        )
        try home.write(
            [
                derived("f1"), TranscriptHome.reply("s1", output: 1), TranscriptHome.reply("f1", output: 10),
                TranscriptHome.reply("f2", output: 100),
            ],
            session: "f2")
        for (session, age) in [("s", 300.0), ("f1", 200), ("f2", 100)] {
            try FileManager.default.setAttributes(
                [.modificationDate: TranscriptHome.now.addingTimeInterval(-age)],
                ofItemAtPath: home.file(session: session).path(percentEncoded: false))
        }
    }

    @Test func chainedForksKeepTheirOwnTokens() async throws {
        let home = try TranscriptHome()
        try writeForkChain(home)

        let found = try await sessions(home.transcripts())

        #expect(found.mapValues(\.total.output) == ["s": 1, "f1": 10, "f2": 100])
    }

    @Test func chainedForksKeepTheirOwnTokensWhenReadInSteps() async throws {
        let home = try TranscriptHome()
        try writeForkChain(home)
        let transcripts = home.transcripts(budget: .zero)

        _ = try await transcripts.activity(since: since)
        let found = try await sessions(transcripts)

        #expect(found.mapValues(\.total.output) == ["s": 1, "f1": 10, "f2": 100])
    }

    @Test func failingIndexWriteIsCounted() async throws {
        let home = try TranscriptHome()
        try home.write([TranscriptHome.reply("m1")])
        // The index's folder is a file: the write cannot succeed.
        try Data().write(to: home.root.appending(path: "state"))

        let transcripts = home.transcripts()
        _ = try await transcripts.activity(since: since)

        #expect(await transcripts.indexWriteFailures == 1)
    }

    @Test func indexIsWrittenAtMostEveryThirtySeconds() async throws {
        let home = try TranscriptHome()
        let clock = TestClock(TranscriptHome.now)
        let transcripts = ClaudeTranscripts(
            claudeHome: home.root, indexFile: home.indexFile, now: { clock.now }, readBudget: .seconds(60))
        try home.write([TranscriptHome.reply("m1")])
        _ = try await transcripts.activity(since: since)

        try home.append(TranscriptHome.reply("m2") + "\n")
        _ = try await transcripts.activity(since: since)
        let afterBurst = await transcripts.indexWrites
        clock.advance(by: 31)
        try home.append(TranscriptHome.reply("m3") + "\n")
        _ = try await transcripts.activity(since: since)

        #expect(afterBurst == 1)
        #expect(await transcripts.indexWrites == 2)
    }

    @Test func pendingChangesAreWrittenOnRequest() async throws {
        let home = try TranscriptHome()
        let transcripts = home.transcripts()
        try home.write([TranscriptHome.reply("m1")])
        _ = try await transcripts.activity(since: since)
        try home.append(TranscriptHome.reply("m2") + "\n")
        _ = try await transcripts.activity(since: since)

        await transcripts.persistIndex()

        #expect(await transcripts.indexWrites == 2)
    }

    @Test func healthTravelsWithTheActivity() async throws {
        let home = try TranscriptHome()
        try home.copySynthetic("malformed.jsonl")

        let activity = try await home.transcripts().activity(since: since)

        #expect(activity.health.skippedLines == 1)
    }
}
