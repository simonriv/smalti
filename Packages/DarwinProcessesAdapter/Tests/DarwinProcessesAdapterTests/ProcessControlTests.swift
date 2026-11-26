import DarwinProcessesAdapter
import Foundation
import SmaltiCore
import Testing

/// C2 of F8 at the adapter: only the test's own children are ever signalled; launchd, this process and a stale
/// identity are refused before any signal.
@Suite("DarwinProcessControl", .serialized)
struct ProcessControlTests {
    private let control = DarwinProcessControl()
    private let processes = DarwinRunningProcesses()

    private func identity(of pid: Int32) async throws -> ProcessIdentity {
        try #require(await processes.current().records.first { $0.pid == pid }?.identity)
    }

    private func waitForExit(_ child: Child, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while child.process.isRunning, Date() < deadline { usleep(20_000) }
        return !child.process.isRunning
    }

    @Test func stopEndsAChildThatListens() async throws {
        let child = try Child.sleeper()
        defer { child.end() }

        try await control.stop(try await identity(of: child.pid))

        #expect(waitForExit(child))
        #expect(child.process.terminationReason == .uncaughtSignal)
        #expect(child.process.terminationStatus == SIGTERM)
    }

    @Test func forceStopEndsAChildThatIgnoresTerm() async throws {
        let child = try Child.sleeper(ignoringTerm: true)
        defer { child.end() }
        let process = try await identity(of: child.pid)
        try await control.stop(process)
        #expect(!waitForExit(child, timeout: 0.5))

        try await control.forceStop(process)

        #expect(waitForExit(child))
        #expect(child.process.terminationStatus == SIGKILL)
    }

    @Test func lowerPrioritySetsNice() async throws {
        let child = try Child.sleeper()
        defer { child.end() }

        try await control.lowerPriority(try await identity(of: child.pid), to: 5)

        #expect(getpriority(PRIO_PROCESS, id_t(child.pid)) == 5)
    }

    @Test func raisingPriorityIsRefusedWithoutCalling() async throws {
        let child = try Child.sleeper()
        defer { child.end() }
        let process = try await identity(of: child.pid)
        try await control.lowerPriority(process, to: 10)

        await #expect(throws: ProcessControlError.refused(code: EACCES)) {
            try await control.lowerPriority(process, to: 5)
        }
        #expect(getpriority(PRIO_PROCESS, id_t(child.pid)) == 10)
    }

    @Test func launchdIsNotYours() async throws {
        let launchd = try await identity(of: 1)

        await #expect(throws: ProcessControlError.notYours) { try await control.stop(launchd) }
        await #expect(throws: ProcessControlError.notYours) { try await control.forceStop(launchd) }
        await #expect(throws: ProcessControlError.notYours) { try await control.lowerPriority(launchd, to: 20) }
    }

    @Test func thisProcessIsNotYours() async throws {
        let own = try await identity(of: getpid())

        await #expect(throws: ProcessControlError.notYours) { try await control.forceStop(own) }
    }

    @Test func staleIdentityIsGoneAndNothingIsSignalled() async throws {
        let child = try Child.sleeper()
        defer { child.end() }
        let real = try await identity(of: child.pid)
        let stale = ProcessIdentity(pid: child.pid, startedAt: real.startedAt.addingTimeInterval(-3600))

        await #expect(throws: ProcessControlError.gone) { try await control.forceStop(stale) }

        #expect(child.process.isRunning)
    }

    @Test func endedProcessIsGone() async throws {
        let child = try Child.sleeper()
        let process = try await identity(of: child.pid)
        child.end()

        await #expect(throws: ProcessControlError.gone) { try await control.stop(process) }
    }
}
