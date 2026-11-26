import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// C4 of F8: nothing samples while the view is closed; the refresher reads only between start and stop.
@MainActor
@Suite("ProcessesRefresher")
struct ProcessesRefresherTests {
    private typealias F = ProcessFixtures
    private let fast = ProcessesRefresher.Timing(first: .milliseconds(5), every: .milliseconds(5))

    private func observe(_ running: FakeRunningProcesses, _ ports: FakeListeningPorts) -> ObserveProcesses {
        ObserveProcesses(processes: running, ports: ports)
    }

    @Test func nothingIsReadBeforeStart() async throws {
        let running = FakeRunningProcesses(samples: [F.sample([F.record(10)])])
        let ports = FakeListeningPorts()
        _ = ProcessesRefresher(observe: observe(running, ports), timing: fast)

        try await Task.sleep(for: .milliseconds(40))

        #expect(await running.reads == 0)
        #expect(await ports.reads == 0)
    }

    @Test func readsWhileRunningAndStopsWhenStopped() async throws {
        let running = FakeRunningProcesses(samples: [F.sample([F.record(10)])])
        let ports = FakeListeningPorts()
        let refresher = ProcessesRefresher(observe: observe(running, ports), timing: fast)
        var snapshots = 0
        refresher.start(foregroundGroups: { [:] }) { _ in snapshots += 1 }
        for _ in 0..<200 where snapshots < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(snapshots >= 2)

        refresher.stop()
        // A read already on its way may still land; no new one may start.
        try await Task.sleep(for: .milliseconds(30))
        let readsAtStop = await running.reads
        try await Task.sleep(for: .milliseconds(60))

        #expect(await running.reads == readsAtStop)
        #expect(!refresher.isRunning)
    }

    @Test func stopForgetsThePreviousSample() async throws {
        let first = F.sample([F.record(10, cpuTime: 0)], at: 10)
        let second = F.sample([F.record(10, cpuTime: F.second)], at: 12)
        let observe = observe(FakeRunningProcesses(samples: [first, second]), FakeListeningPorts())
        let refresher = ProcessesRefresher(observe: observe, timing: fast)
        _ = await observe.refresh(foregroundGroups: [:])

        refresher.stop()

        #expect(await observe.refresh(foregroundGroups: [:]).cpu.isEmpty)
    }

    @Test func refreshNowReadsOnceWhileRunningOnly() async throws {
        let running = FakeRunningProcesses(samples: [F.sample([F.record(10)])])
        let refresher = ProcessesRefresher(
            observe: observe(running, FakeListeningPorts()), timing: .init(first: .seconds(60), every: .seconds(60)))

        await refresher.refreshNow()
        #expect(await running.reads == 0)

        refresher.start(foregroundGroups: { [:] }) { _ in }
        for _ in 0..<200 where await running.reads == 0 { try await Task.sleep(for: .milliseconds(10)) }
        let before = await running.reads
        await refresher.refreshNow()

        #expect(await running.reads == before + 1)
        refresher.stop()
    }
}
