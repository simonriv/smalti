import ClaudeHarnessAdapter
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Claude's fixture: F3's real transcripts moved to `/private/tmp/smalti-fx/claude` (plan T1).
enum ClaudeFixture {
    static var description: HarnessFixtureDescription {
        get throws {
            let source = try #require(Bundle.module.url(forResource: "Fixtures/claude", withExtension: nil))
            return HarnessFixtureDescription(
                harness: .claude, source: source, processName: "claude", resume: { "claude --resume \($0)" },
                continueCommand: "claude --continue", fork: { "claude --resume \($0) --fork-session" },
                commandLine: { ["claude", "--resume", $0] },
                modifiedFile: { id in
                    let folder =
                        ["401a63e1-c076-45fe-9f09-432da1c8cfa6", "0259e0a5-46f8-44f8-bc38-edfa7d1a0f2b"]
                            .contains(id) ? "work-a" : "work-b"
                    return ".claude/projects/-private-tmp-smalti-fx-claude-\(folder)/\(id).jsonl"
                })
        }
    }

    static func harness(home: URL) -> ClaudeHarness {
        ClaudeHarness(projectsRoot: home.appending(path: ".claude/projects"))
    }
}

@Suite("ClaudeHarness", .serialized)
struct ClaudeHarnessTests {
    private func agent(_ id: String) -> AgentSnapshot {
        AgentSnapshot(harness: .claude, sessionID: id, title: nil, lastState: .waiting)
    }

    private let detached = ClaudeHarness(projectsRoot: URL(filePath: "/private/tmp/smalti-fx/none"))

    @Test func claudeSatisfiesTheHarnessContract() async throws {
        try await HarnessAdapterContract.verify(
            fixture: try ClaudeFixture.description, make: ClaudeFixture.harness,
            breakSchema: { home in
                let projects = home.appending(path: ".claude/projects")
                let files = FileManager.default.enumerator(at: projects, includingPropertiesForKeys: nil)
                while let file = files?.nextObject() as? URL {
                    guard file.pathExtension == "jsonl" else { continue }
                    let text = try String(contentsOf: file, encoding: .utf8)
                    try text.replacingOccurrences(of: "\"cwd\"", with: "\"folder\"").write(
                        to: file, atomically: true, encoding: .utf8)
                }
            })
    }

    @Test func resumeCommandUsesSessionID() {
        #expect(detached.resumeCommand(sessionID: "7f3a9c2e") == "claude --resume 7f3a9c2e")
    }

    @Test func ideFlagAppended() {
        #expect(detached.resumeCommandConnectingEditor(sessionID: "7f3a") == "claude --resume 7f3a --ide")
    }

    @Test func readsShortResumeFlag() {
        #expect(detached.sessionID(fromCommandLine: ["claude", "-r", "7f3a"]) == "7f3a")
        #expect(detached.sessionID(fromCommandLine: ["claude", "--continue"]) == nil)
        #expect(detached.sessionID(fromCommandLine: ["codex", "resume", "7f3a"]) == nil)
    }

    @Test func forkIsNotTheOriginalSession() {
        #expect(detached.sessionID(fromCommandLine: ["claude", "--resume", "7f3a", "--fork-session"]) == nil)
    }

    /// I2: the capture reads only the project folder of the pane's directory, so a session with the same cwd in
    /// another folder is never even opened.
    @Test func captureReadsOnlyTheProjectFolderOfTheDirectory() async throws {
        let home = try FixtureHome.materialize(try ClaudeFixture.description)
        let projects = home.appending(path: ".claude/projects")
        let work = "/private/tmp/smalti-fx/claude/work-b"
        let decoy = projects.appending(path: "-elsewhere")
        try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
        let line = #"{"type":"user","cwd":"\#(work)","timestamp":"2026-11-26T00:00:00Z","message":{"content":"x"}}"#
        try line.write(to: decoy.appending(path: "decoy-1.jsonl"), atomically: true, encoding: .utf8)
        let real = projects.appending(path: "-private-tmp-smalti-fx-claude-work-b/fresh-1.jsonl")
        try line.write(to: real, atomically: true, encoding: .utf8)
        let window = CaptureWindow(directory: work, processStartedAt: Date().addingTimeInterval(-1), excludedIDs: [])

        #expect(try await ClaudeFixture.harness(home: home).captureSessionId(in: window) == "fresh-1")
    }

    @Test func captureIgnoresTranscriptsBornBeforeTheStart() async throws {
        let home = try FixtureHome.materialize(try ClaudeFixture.description)
        let window = CaptureWindow(
            directory: "/private/tmp/smalti-fx/claude/work-a", processStartedAt: Date().addingTimeInterval(60),
            excludedIDs: [])

        #expect(try await ClaudeFixture.harness(home: home).captureSessionId(in: window) == nil)
    }

    @Test func listingReadsOnlyTheNewestTranscripts() async throws {
        let home = try FixtureHome.materialize(try ClaudeFixture.description)
        let folder = home.appending(path: ".claude/projects/-private-tmp-smalti-fx-claude-work-a")
        for (index, age) in [3e8, 2e8, 1e8].enumerated() {
            let file = folder.appending(path: "old-\(index).jsonl")
            let line =
                #"{"type":"user","cwd":"/private/tmp/smalti-fx/claude/work-a","timestamp":"2026-11-27T00:00:0\#(index)Z","message":{"content":"old"}}"#
            try line.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        }

        let sessions = try await ClaudeFixture.harness(home: home).listSessions(SessionQuery(limit: 3))

        #expect(!sessions.map(\.id).contains { $0.hasPrefix("old-") })
    }

    @Test func subagentTranscriptsAreNotSessions() async throws {
        let home = try FixtureHome.materialize(try ClaudeFixture.description)
        let folder = home.appending(path: ".claude/projects/-private-tmp-smalti-fx-claude-work-a/x/subagents")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"type":"user","cwd":"/private/tmp/smalti-fx/claude/work-a","timestamp":"2026-11-26T00:00:00Z"}"#
            .write(to: folder.appending(path: "agent-1.jsonl"), atomically: true, encoding: .utf8)

        let sessions = try await ClaudeFixture.harness(home: home).listSessions(SessionQuery())

        #expect(!sessions.map(\.id).contains("agent-1"))
    }

    @Test func malformedTranscriptIsSkipped() async throws {
        let home = try FixtureHome.materialize(try ClaudeFixture.description)
        let folder = home.appending(path: ".claude/projects/-private-tmp-smalti-fx-claude-work-a")
        try "not json\n{".write(to: folder.appending(path: "broken.jsonl"), atomically: true, encoding: .utf8)

        let sessions = try await ClaudeFixture.harness(home: home).listSessions(SessionQuery())

        #expect(sessions.count == 3)
    }
}
