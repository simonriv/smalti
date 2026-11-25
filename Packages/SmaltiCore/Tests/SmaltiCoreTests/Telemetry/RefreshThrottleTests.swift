import Foundation
import SmaltiCore
import Testing

/// Review 2: telemetry batches refresh the open observatory at most once per interval.
@Suite("Refresh throttle")
struct RefreshThrottleTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func firstRequestRefreshes() {
        var throttle = RefreshThrottle(interval: 2)

        let refreshes = throttle.shouldRefresh(at: start)

        #expect(refreshes)
    }

    @Test func requestsWithinTheIntervalWait() {
        var throttle = RefreshThrottle(interval: 2)
        _ = throttle.shouldRefresh(at: start)

        let early = throttle.shouldRefresh(at: start.addingTimeInterval(1.9))
        let onTime = throttle.shouldRefresh(at: start.addingTimeInterval(2))

        #expect(!early)
        #expect(onTime)
    }

    @Test func aRefusedRequestDoesNotMoveTheWindow() {
        var throttle = RefreshThrottle(interval: 2)
        _ = throttle.shouldRefresh(at: start)
        _ = throttle.shouldRefresh(at: start.addingTimeInterval(1))

        let later = throttle.shouldRefresh(at: start.addingTimeInterval(2.5))

        #expect(later)
    }
}
