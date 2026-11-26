import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("LowerPriority")
struct LowerPriorityTests {
    private typealias F = ProcessFixtures

    private func row(nice: Int32, verdict: StopVerdict = .allowed) -> ProcessRow {
        ProcessRow(
            record: F.record(10, nice: nice), pane: nil, cpu: nil, state: .idle, verdict: verdict, treePrefix: "",
            depth: 0, isContext: false)
    }

    @Test func lowersOneStep() async {
        let control = FakeProcessControl()

        let outcome = await LowerPriority(control: control).lower(row(nice: 0))

        #expect(outcome == .lowered(to: 5))
        #expect(await control.calls == [.lowerPriority(ProcessIdentity(pid: 10, startedAt: F.start), 5)])
    }

    @Test func lowestDoesNotCall() async {
        let control = FakeProcessControl()

        #expect(await LowerPriority(control: control).lower(row(nice: 20)) == .alreadyLowest)
        #expect(await control.calls.isEmpty)
    }

    @Test func protectedDoesNotCall() async {
        let control = FakeProcessControl()

        #expect(await LowerPriority(control: control).lower(row(nice: 0, verdict: .protected(.system))) == .protected(.system))
        #expect(await control.calls.isEmpty)
    }

    @Test func failureIsReported() async {
        let control = FakeProcessControl()
        await control.fail(with: .refused(code: 13))

        #expect(await LowerPriority(control: control).lower(row(nice: 5)) == .failed(.refused(code: 13)))
    }
}
