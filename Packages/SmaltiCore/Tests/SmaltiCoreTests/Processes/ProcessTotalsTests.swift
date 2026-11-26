import SmaltiCore
import Testing

@Suite("ProcessTotals")
struct ProcessTotalsTests {
    private typealias F = ProcessFixtures

    @Test func sumsOwnProcessesAndThePanesPart() {
        let pane = PaneID()
        let records = [
            F.record(101, isOwn: false, terminal: 7, memory: 999),
            F.record(102, parent: 101, terminal: 7, memory: 100),
            F.record(200, memory: 50),
        ]
        let cpu = [
            ProcessIdentity(pid: 102, startedAt: F.start): 10.0, ProcessIdentity(pid: 200, startedAt: F.start): 2.5,
        ]
        let attribution = PaneAttribution(records: records, foregroundGroups: [pane: 102])

        let totals = ProcessTotals.of(F.sample(records, hidden: 3), cpu: cpu, attribution: attribution)

        #expect(totals.count == 2)
        #expect(totals.hidden == 3)
        #expect(totals.cpu == 12.5)
        #expect(totals.memory == 150)
        #expect(totals.paneMemory == 100)
        #expect(totals.memoryTotal == 16 << 30)
    }

    @Test func noCPUYetIsNil() {
        let totals = ProcessTotals.of(
            F.sample([F.record(1)]), cpu: [:], attribution: PaneAttribution(records: [], foregroundGroups: [:]))

        #expect(totals.cpu == nil)
    }
}
