import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("ObserveProcesses", .timeLimit(.minutes(1)))
struct ObserveProcessesTests {
    private typealias F = ProcessFixtures
    private let pane = PaneID()

    @Test func cpuAppearsFromTheSecondRefresh() async {
        let first = F.sample([F.record(10, terminal: 4, cpuTime: 0)], at: 10)
        let second = F.sample([F.record(10, terminal: 4, cpuTime: F.second)], at: 12)
        let observe = ObserveProcesses(
            processes: FakeRunningProcesses(samples: [first, second]), ports: FakeListeningPorts())

        let before = await observe.refresh(foregroundGroups: [pane: 10])
        let after = await observe.refresh(foregroundGroups: [pane: 10])

        #expect(before.cpu.isEmpty)
        #expect(after.cpu[ProcessIdentity(pid: 10, startedAt: F.start)] == 50)
        #expect(after.attribution.pane(of: 10) == pane)
    }

    @Test func socketsComeWithTheSample() async {
        let socket = ListeningSocket(pid: 10, transport: .tcp, port: 5173, address: "127.0.0.1")
        let observe = ObserveProcesses(
            processes: FakeRunningProcesses(samples: [F.sample([F.record(10)])]),
            ports: FakeListeningPorts(sockets: [socket]))

        let snapshot = await observe.refresh(foregroundGroups: [:])

        #expect(snapshot.sockets == [socket])
        #expect(snapshot.alive == [ProcessIdentity(pid: 10, startedAt: F.start)])
    }

    /// Final review (minor 5): a read that lands after a reset (the view closed meanwhile) does not become the next
    /// opening's previous sample.
    @Test func readLandingAfterResetIsNotKept() async throws {
        let first = F.sample([F.record(10, cpuTime: 0)], at: 10)
        let second = F.sample([F.record(10, cpuTime: F.second)], at: 12)
        let running = FakeRunningProcesses(samples: [first, second])
        let observe = ObserveProcesses(processes: running, ports: FakeListeningPorts())

        let landing = Task { await observe.refresh(foregroundGroups: [:]) }
        for _ in 0..<400 where await running.reads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        observe.reset()
        _ = await landing.value

        #expect(await observe.refresh(foregroundGroups: [:]).cpu.isEmpty)
    }

    @Test func resetForgetsThePreviousSample() async {
        let first = F.sample([F.record(10, cpuTime: 0)], at: 10)
        let second = F.sample([F.record(10, cpuTime: F.second)], at: 12)
        let observe = ObserveProcesses(
            processes: FakeRunningProcesses(samples: [first, second]), ports: FakeListeningPorts())
        _ = await observe.refresh(foregroundGroups: [:])

        observe.reset()

        #expect(await observe.refresh(foregroundGroups: [:]).cpu.isEmpty)
    }
}
