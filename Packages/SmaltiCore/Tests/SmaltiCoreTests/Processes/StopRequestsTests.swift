import SmaltiCore
import Testing

@Suite("StopRequests")
struct StopRequestsTests {
    private let node = ProcessIdentity(pid: 10, startedAt: ProcessFixtures.start)
    private let grace: UInt64 = 3

    @Test func requestWaitsThroughTheGrace() {
        var requests = StopRequests()
        requests.request(node, at: 100)

        requests.tick(alive: [node], now: 102, grace: grace)

        #expect(requests.phase(of: node) == .requested(at: 100))
    }

    @Test func stillAliveAfterTheGraceIsUnresponsive() {
        var requests = StopRequests()
        requests.request(node, at: 100)

        requests.tick(alive: [node], now: 103, grace: grace)

        #expect(requests.phase(of: node) == .unresponsive)
    }

    @Test func goneProcessLeavesNoRequest() {
        var requests = StopRequests()
        requests.request(node, at: 100)

        requests.tick(alive: [], now: 101, grace: grace)

        #expect(requests.phase(of: node) == nil)
        #expect(requests.phases.isEmpty)
    }

    @Test func onlyUnresponsiveCanAskToForce() {
        var requests = StopRequests()
        requests.request(node, at: 100)

        let early = requests.askToForce(node)
        requests.tick(alive: [node], now: 200, grace: grace)
        let late = requests.askToForce(node)

        #expect(!early)
        #expect(late)
        #expect(requests.phase(of: node) == .confirming)
    }

    @Test func unknownCannotAskToForce() {
        var requests = StopRequests()

        let asked = requests.askToForce(node)

        #expect(!asked)
        #expect(requests.phase(of: node) == nil)
    }

    @Test func cancelGoesBackToUnresponsive() {
        var requests = StopRequests()
        requests.request(node, at: 0)
        requests.tick(alive: [node], now: 10, grace: grace)
        _ = requests.askToForce(node)

        requests.cancel(node)

        #expect(requests.phase(of: node) == .unresponsive)
    }

    @Test func cancelOutsideConfirmingChangesNothing() {
        var requests = StopRequests()
        requests.request(node, at: 0)

        requests.cancel(node)

        #expect(requests.phase(of: node) == .requested(at: 0))
    }

    @Test func confirmingDoesNotTickBack() {
        var requests = StopRequests()
        requests.request(node, at: 0)
        requests.tick(alive: [node], now: 10, grace: grace)
        _ = requests.askToForce(node)

        requests.tick(alive: [node], now: 20, grace: grace)

        #expect(requests.phase(of: node) == .confirming)
    }
}
