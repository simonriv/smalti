import SmaltiCore
import Testing

@Suite("HandlePaneExit")
struct HandlePaneExitTests {
    private let handle = HandlePaneExit()

    @Test func shellThatRanNormallyClosesThePane() {
        #expect(handle.execute(exitCode: 0, lifetime: .seconds(5)) == .closePane)
    }

    @Test func failingCommandAfterAWhileStillClosesThePane() {
        #expect(handle.execute(exitCode: 1, lifetime: .seconds(30)) == .closePane)
    }

    @Test func shellDyingRightAfterStartIsReported() {
        #expect(handle.execute(exitCode: 127, lifetime: .milliseconds(80)) == .reportFailedStart(exitCode: 127))
    }

    @Test func unknownExitCodeRightAfterStartIsReported() {
        #expect(handle.execute(exitCode: nil, lifetime: .zero) == .reportFailedStart(exitCode: nil))
    }

    @Test func exactlyTheMinimumLifetimeCountsAsHealthy() {
        #expect(handle.execute(exitCode: 0, lifetime: HandlePaneExit.minimumHealthyLifetime) == .closePane)
    }
}
