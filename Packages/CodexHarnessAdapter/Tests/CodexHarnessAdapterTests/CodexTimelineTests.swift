@testable import CodexHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Read-only fixtures: F6's Codex home (text replies) and F9's (two turns with shell tools, one failing).
enum CodexTimelineFixtures {
    static let fixtures = TimelineOracle.repository.appending(
        path: "Packages/CodexHarnessAdapter/Tests/CodexHarnessAdapterTests/Fixtures")
    static let f6Home = fixtures.appending(path: "codex/home/codex")
    static let toolsHome = fixtures.appending(path: "codex-timeline/home/codex")
    static let toolsSession = "01a217ec-6769-7511-85da-e8c0c0fc852a"
    static let toolsRoot = "/private/tmp/smalti-fx/codex-timeline/work-a"

    static func rollout(_ home: URL, _ id: String) throws -> URL {
        let enumerator = FileManager.default.enumerator(
            at: home.appending(path: "sessions"), includingPropertiesForKeys: nil)
        let files = (enumerator?.allObjects as? [URL]) ?? []
        return try #require(files.first { $0.lastPathComponent.hasSuffix("\(id).jsonl") })
    }
}

@Suite("CodexTimeline")
struct CodexTimelineTests {
    private typealias F = CodexTimelineFixtures

    @Test(arguments: [
        (F.f6Home, "01a210a3-2dac-78c0-ae6f-c353ab314277"), (F.f6Home, "01a210a3-a395-76d2-907f-4477c88dcc16"),
        (F.toolsHome, F.toolsSession),
    ])
    func rolloutsMatchTheOracle(home: URL, id: String) async throws {
        let oracle = try TimelineOracle.items(harness: .codex, transcript: try F.rollout(home, id))

        try await TranscriptsContract.verify(CodexTimeline(home: home), sessionID: id, oracle: oracle)
    }

    @Test func aFailingCommandFailsWithItsExitCode() async throws {
        let adapter = CodexTimeline(home: F.toolsHome)
        let read = try await adapter.read(try await adapter.locate(sessionID: F.toolsSession), from: .start)

        let timeline = Timeline().appending(read.entries)

        let statuses = timeline.turns.flatMap(\.items).compactMap { item -> ToolStatus? in
            if case .tool(let tool) = item { tool.status } else { nil }
        }
        #expect(statuses == [.done, .failed(exitCode: 1)])
        #expect(timeline.turnCount == 2)
    }

    @Test func summariesShowTheCommand() async throws {
        let adapter = CodexTimeline(home: F.toolsHome)
        let read = try await adapter.read(try await adapter.locate(sessionID: F.toolsSession), from: .start)

        let summaries = read.entries.compactMap { entry -> String? in
            guard case .toolCall(let call) = entry.kind else { return nil }
            return ToolSummary.text(name: call.name, input: call.arguments, diff: nil)
        }

        #expect(summaries == ["ls", "cat missing.txt"])
    }

    @Test func projectSessionsComeFromTheIndex() async throws {
        let adapter = CodexTimeline(home: F.toolsHome)

        #expect(try await adapter.sessions(under: F.toolsRoot, limit: 5).map(\.id) == [F.toolsSession])
        #expect(try await adapter.sessions(under: "/private/tmp/smalti-fx/codex-timeline", limit: 5).count == 1)
        #expect(try await adapter.sessions(under: "/private/tmp/smalti-fx/codex-timeline/work", limit: 5).isEmpty)
    }

    @Test func searchFindsAFailedOutput() async throws {
        var hits: [TranscriptHit] = []

        for try await hit in CodexTimeline(home: F.toolsHome).search(TimelineQuery("No such file"), under: F.toolsRoot)
        {
            hits.append(hit)
        }

        #expect(hits.contains { $0.text.contains("cat: missing.txt: No such file or directory") })
    }

    @Test func aCompressedRolloutIsCompressed() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "codex-zst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.copyItem(
            at: F.toolsHome.appending(path: "state_5.sqlite"), to: home.appending(path: "state_5.sqlite"))
        let write = Process()
        write.executableURL = URL(filePath: "/usr/bin/sqlite3")
        write.arguments = [
            home.appending(path: "state_5.sqlite").path, "update threads set rollout_path = rollout_path || '.zst'",
        ]
        try write.run()
        write.waitUntilExit()

        await #expect(throws: TranscriptReadError.self) {
            try await CodexTimeline(home: home).locate(sessionID: F.toolsSession)
        }
        do {
            _ = try await CodexTimeline(home: home).locate(sessionID: F.toolsSession)
        } catch {
            if case .compressed = error {} else { Issue.record("expected compressed, got \(error)") }
        }
    }

    /// A copy of the tools home whose index points the session at `rollout`.
    private func home(with rollout: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "codex-tl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: F.toolsHome.appending(path: "state_5.sqlite"), to: home.appending(path: "state_5.sqlite"))
        let file = home.appending(path: "rollout.jsonl")
        try Data(rollout.utf8).write(to: file)
        let write = Process()
        write.executableURL = URL(filePath: "/usr/bin/sqlite3")
        write.arguments = [
            home.appending(path: "state_5.sqlite").path, "update threads set rollout_path = '\(file.path)'",
        ]
        try write.run()
        write.waitUntilExit()
        return home
    }

    @Test func multipartMessagesCustomToolsAndCompactionsMatchTheOracle() async throws {
        let lines = [
            #"{"timestamp":"2026-11-26T10:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"uno"},{"type":"input_text","text":"dos"}]}}"#,
            #"{"timestamp":"2026-11-26T10:00:01.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\n*** Add File: a.txt\n+x\n*** End Patch","call_id":"c1"}}"#,
            #"{"timestamp":"2026-11-26T10:00:02.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"c1","output":{"content":"Done!","metadata":{"exit_code":0}}}}"#,
            #"{"timestamp":"2026-11-26T10:00:03.000Z","type":"compacted","payload":{"message":""}}"#,
            #"{"timestamp":"2026-11-26T10:00:04.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"a"},{"type":"output_text","text":"b"}]}}"#,
        ]
        let home = try home(with: lines.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let oracle = try TimelineOracle.items(harness: .codex, transcript: home.appending(path: "rollout.jsonl"))

        try await TranscriptsContract.verify(CodexTimeline(home: home), sessionID: F.toolsSession, oracle: oracle)
        #expect(oracle.map(\.kind) == ["prompt", "call", "output", "compaction", "reply"])
    }

    @Test func searchMeetsTheContract() async throws {
        let oracle = try TimelineOracle.items(harness: .codex, transcript: try F.rollout(F.toolsHome, F.toolsSession))

        try await TranscriptsContract.verifySearch(CodexTimeline(home: F.toolsHome), root: F.toolsRoot, oracle: oracle)
    }

    @Test func anUnreadableRolloutFails() async throws {
        let home = try home(with: "{}\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = CodexTimeline(home: home)
        let ref = try await adapter.locate(sessionID: F.toolsSession)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ref.file)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ref.file) }

        await #expect(throws: TranscriptReadError.self) { try await adapter.read(ref, from: .start) }
    }

    @Test func anUnknownSessionIsMissing() async {
        await #expect(throws: TranscriptReadError.self) {
            try await CodexTimeline(home: F.toolsHome).locate(sessionID: "nope")
        }
    }
}
