import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("StopProcess")
struct StopProcessTests {
    private typealias F = ProcessFixtures
    private let grace: UInt64 = 3

    private func row(_ record: ProcessRecord, verdict: StopVerdict = .allowed) -> ProcessRow {
        let attribution = PaneAttribution(records: [record], foregroundGroups: [:])
        let input = ProcessTableInput(
            sample: F.sample([record]), cpu: [:], attribution: attribution, policy: StopPolicy(ownPID: 1),
            paneNames: [:], phases: [:])
        let base = ProcessTable.rowsByPID(input)[record.pid]
        return ProcessRow(
            record: record, pane: nil, cpu: base?.cpu, state: .idle, verdict: verdict, treePrefix: "", depth: 0,
            isContext: false)
    }

    private var node: ProcessRow { row(F.record(10, name: "node")) }

    @Test func protectedNeverReachesThePort() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)

        let outcome = await stop.press(row(F.record(10), verdict: .protected(.paneShell)), now: 0)

        #expect(outcome == .protected(.paneShell))
        #expect(await control.calls.isEmpty)
    }

    @Test func firstPressAsksToStop() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)

        let outcome = await stop.press(node, now: 5)

        #expect(outcome == .requested)
        #expect(await control.calls == [.stop(node.identity)])
        #expect(stop.requests.phase(of: node.identity) == .requested(at: 5))
    }

    @Test func pressWithinTheGraceWaits() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)

        let outcome = await stop.press(node, now: 6)

        #expect(outcome == .waiting)
        #expect(await control.calls.count == 1)
    }

    @Test func pressWhenUnresponsiveAsksForConfirmationWithoutForcing() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)
        stop.tick(alive: [node.identity], now: 9)

        let outcome = await stop.press(node, now: 9)

        #expect(outcome == .confirming)
        #expect(await control.calls == [.stop(node.identity)])
    }

    @Test func confirmForcesOnce() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)
        stop.tick(alive: [node.identity], now: 9)
        _ = await stop.press(node, now: 9)

        let outcome = await stop.confirm(node.identity)

        #expect(outcome == .forced)
        #expect(await control.calls == [.stop(node.identity), .forceStop(node.identity)])
        #expect(stop.requests.phase(of: node.identity) == nil)
    }

    @Test func confirmWithoutRequestDoesNothing() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)

        #expect(await stop.confirm(node.identity) == .waiting)
        #expect(await control.calls.isEmpty)
    }

    @Test func confirmWithinTheGraceDoesNothing() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)

        #expect(await stop.confirm(node.identity) == .waiting)
        #expect(await control.calls == [.stop(node.identity)])
    }

    @Test func confirmWhenUnresponsiveButNotAskedDoesNothing() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)
        stop.tick(alive: [node.identity], now: 9)

        #expect(await stop.confirm(node.identity) == .waiting)
        #expect(await control.calls.count == 1)
    }

    @Test func cancelKeepsItUnresponsive() async {
        let stop = StopProcess(control: FakeProcessControl(), grace: grace)
        _ = await stop.press(node, now: 5)
        stop.tick(alive: [node.identity], now: 9)
        _ = await stop.press(node, now: 9)

        stop.cancel(node.identity)

        #expect(stop.requests.phase(of: node.identity) == .unresponsive)
    }

    @Test func failedStopLeavesNoRequest() async {
        let control = FakeProcessControl()
        await control.fail(with: .gone)
        let stop = StopProcess(control: control, grace: grace)

        let outcome = await stop.press(node, now: 5)

        #expect(outcome == .failed(.gone))
        #expect(stop.requests.phase(of: node.identity) == nil)
    }

    @Test func failedForceOfAGoneProcessForgetsIt() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)
        stop.tick(alive: [node.identity], now: 9)
        _ = await stop.press(node, now: 9)
        await control.fail(with: .gone)

        #expect(await stop.confirm(node.identity) == .failed(.gone))
        #expect(stop.requests.phase(of: node.identity) == nil)
    }

    @Test func failedForceForAnotherReasonStaysUnresponsive() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)
        stop.tick(alive: [node.identity], now: 9)
        _ = await stop.press(node, now: 9)
        await control.fail(with: .refused(code: 1))

        #expect(await stop.confirm(node.identity) == .failed(.refused(code: 1)))
        #expect(stop.requests.phase(of: node.identity) == .unresponsive)
    }

    @Test func pressWhileConfirmingStaysConfirming() async {
        let control = FakeProcessControl()
        let stop = StopProcess(control: control, grace: grace)
        _ = await stop.press(node, now: 5)
        stop.tick(alive: [node.identity], now: 9)
        _ = await stop.press(node, now: 9)

        #expect(await stop.press(node, now: 10) == .confirming)
        #expect(await control.calls.count == 1)
    }
}
