import Darwin
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@testable import ClaudeTelemetryAdapter

/// Processes as the test says they are.
private struct FakeProcesses: ProcessProbe {
    var alive: Set<Int32> = []
    var starts: [Int32: Date] = [:]

    func isAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
    func startTime(of pid: Int32) -> Date? { starts[pid] }
}

@Suite("ClaudeSessionRegistry")
struct ClaudeSessionRegistryTests {
    /// "Mon Nov 23 04:35:02 2026" in UTC, as Claude Code writes `procStart`.
    private let started = Date(timeIntervalSince1970: 1_795_408_502)

    private func home(_ sessions: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "claude-sessions-\(UUID().uuidString)")
        let directory = root.appending(path: "sessions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in sessions { try Data(text.utf8).write(to: directory.appending(path: name)) }
        return root
    }

    private func session(
        pid: Int32, id: String = "s1", status: String = "busy", procStart: String? = "Mon Nov 23 04:35:02 2026"
    ) -> String {
        let start = procStart.map { #","procStart":"\#($0)""# } ?? ""
        return
            #"{"pid":\#(pid),"sessionId":"\#(id)","cwd":"/w/api","startedAt":1795408502446,"status":"\#(status)"\#(start)}"#
    }

    @Test func liveSessionIsReturned() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": session(pid: 101)]),
            processes: FakeProcesses(alive: [101], starts: [101: started]))

        let running = await registry.running()

        #expect(
            running == [
                RunningAgent(
                    pid: 101, sessionID: "s1", cwd: "/w/api", status: "busy",
                    startedAt: Date(timeIntervalSince1970: 1_795_408_502.446))
            ])
    }

    @Test func deadPidIsSkipped() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": session(pid: 101)]), processes: FakeProcesses())

        #expect(await registry.running().isEmpty)
    }

    @Test func reusedPidWithOtherStartIsSkipped() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": session(pid: 101)]),
            processes: FakeProcesses(alive: [101], starts: [101: started.addingTimeInterval(3_600)]))

        #expect(await registry.running().isEmpty)
    }

    @Test func startWithinASecondStillMatches() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": session(pid: 101)]),
            processes: FakeProcesses(alive: [101], starts: [101: started.addingTimeInterval(0.9)]))

        #expect(await registry.running().count == 1)
    }

    @Test func missingProcStartCannotProveTheSession() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": session(pid: 101, procStart: nil)]),
            processes: FakeProcesses(alive: [101]))

        #expect(await registry.running().isEmpty)
    }

    @Test func unreadableProcStartCannotProveTheSession() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": session(pid: 101, procStart: "yesterday")]),
            processes: FakeProcesses(alive: [101], starts: [101: started]))

        #expect(await registry.running().isEmpty)
    }

    @Test func missingStartedAtIsSkipped() async throws {
        let text = #"{"pid":101,"sessionId":"s1","cwd":"/w","status":"busy","procStart":"Mon Nov 23 04:35:02 2026"}"#
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": text]), processes: FakeProcesses(alive: [101], starts: [101: started]))

        #expect(await registry.running().isEmpty)
    }

    @Test func unreadableJsonIsSkipped() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": "{broken", "102.json": session(pid: 102, id: "s2")]),
            processes: FakeProcesses(alive: [101, 102], starts: [102: started]))

        #expect(await registry.running().map(\.sessionID) == ["s2"])
    }

    @Test func keyFilesAreNeverRead() async throws {
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.abc123.key": session(pid: 101), "101.json.key": session(pid: 101)]),
            processes: FakeProcesses(alive: [101], starts: [101: started]))

        #expect(await registry.running().isEmpty)
    }

    @Test func missingSessionsDirectoryIsEmpty() async {
        let registry = ClaudeSessionRegistry(
            claudeHome: FileManager.default.temporaryDirectory.appending(path: "nowhere-\(UUID().uuidString)"),
            processes: FakeProcesses())

        #expect(await registry.running().isEmpty)
    }

    @Test(arguments: ["Mon Nov 23 04:35:02 2026", "Mon Nov  3 04:35:02 2026", "Mon Nov 3 04:35:02 2026"])
    func procStartParsesCtimeInUTC(text: String) {
        let parsed = ClaudeSessionRegistry.processStart(text)

        let day = text.contains("23") ? 23 : 3
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(parsed.map { calendar.component(.day, from: $0) } == day)
        #expect(parsed.map { calendar.component(.hour, from: $0) } == 4)
    }

    @Test func realProbeSeesThisProcess() {
        let probe = DarwinProcessProbe()
        let me = getpid()

        #expect(probe.isAlive(me))
        let start = probe.startTime(of: me)
        #expect(start.map { $0 <= Date() && $0 > Date().addingTimeInterval(-86_400) } == true)
    }

    @Test func registryHonoursTheContract() async throws {
        let processes = FakeProcesses(alive: [101], starts: [101: started])
        let registry = ClaudeSessionRegistry(
            claudeHome: try home(["101.json": session(pid: 101)]), processes: processes)

        await LiveAgentsContract.verify(registry) { processes.isAlive($0) }
    }
}
