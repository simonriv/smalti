import Darwin
import Foundation
import Testing

@testable import GhosttyAdapter

@Suite("Process start")
struct ProcessStartTests {
    @Test func startOfOwnProcessIsBeforeNow() throws {
        let start = try #require(ProcessStart.of(pid: getpid()))

        #expect(start <= Date())
        #expect(start > Date().addingTimeInterval(-24 * 3600))
    }

    @Test func deadPidIsNil() {
        #expect(ProcessStart.of(pid: 999_999) == nil)
        #expect(ProcessStart.of(pid: 0) == nil)
    }

    @Test func trackerEventCarriesPidAndStart() {
        var tracker = ProcessNameTracker()
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let event = tracker.observe("codex", commandLine: { ["codex"] }, pid: 42, startedAt: { start })

        #expect(
            event == .foregroundProcessChanged(.init(name: "codex", commandLine: ["codex"], pid: 42, startedAt: start)))
    }
}
