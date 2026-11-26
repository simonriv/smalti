import Foundation
import SmaltiCore
import Testing

@testable import IPCAdapter

/// Review 1: a guard that arrives while the server stops is denied at once, never left waiting 620 s.
@Suite("Guard waiters")
struct GuardWaitersTests {
    @Test func closedWaitersRefuseNewGuards() {
        let waiters = GuardWaiters()

        waiters.close(GuardTexts.spanish.unreachable)

        #expect(waiters.add() == nil)
    }

    @Test func closingDeniesTheWaitingOnes() {
        let waiters = GuardWaiters()
        let waiter = waiters.add()

        waiters.close(GuardTexts.spanish.unreachable)

        #expect(waiter?.wait(seconds: 1) == .deny(GuardTexts.spanish.unreachable))
    }

    @Test func boundedNumberOfWaiters() {
        let waiters = GuardWaiters()
        let added = (0..<UnixSocketTelemetry.maximumWaitingGuards).compactMap { _ in waiters.add() }

        #expect(added.count == UnixSocketTelemetry.maximumWaitingGuards)
        #expect(waiters.add() == nil)
    }
}
