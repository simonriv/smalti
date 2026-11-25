import Foundation
import SmaltiCore
import Testing

/// F5.6 review 2 (M2, M3): when to ask `claude plugin list` again. A check takes seconds of CPU, so opening ⌘K asks
/// at most every 30 s; launch, install and uninstall always ask, and one asked for while a check runs follows it.
@Suite("IntegrationCheckSchedule")
struct IntegrationCheckScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func firstRequestStarts() {
        var schedule = IntegrationCheckSchedule()

        let answer1 = schedule.shouldStart(forced: false, now: start)
        #expect(answer1)
    }

    @Test func requestWhileCheckingDoesNotStartAnother() {
        var schedule = IntegrationCheckSchedule()
        _ = schedule.shouldStart(forced: true, now: start)

        let answer2 = schedule.shouldStart(forced: false, now: start)
        #expect(!answer2)
        let answer3 = schedule.finished(at: start + 1)
        #expect(!answer3)
    }

    @Test func forcedRequestWhileCheckingRunsAgainAfterIt() {
        var schedule = IntegrationCheckSchedule()
        _ = schedule.shouldStart(forced: false, now: start)

        let answer4 = schedule.shouldStart(forced: true, now: start + 1)
        #expect(!answer4)
        let answer5 = schedule.finished(at: start + 2)
        #expect(answer5)
        let answer6 = schedule.finished(at: start + 3)
        #expect(!answer6)
    }

    @Test func unforcedRequestWaitsTheMinimumInterval() {
        var schedule = IntegrationCheckSchedule()
        _ = schedule.shouldStart(forced: true, now: start)
        _ = schedule.finished(at: start + 1)

        let answer7 = schedule.shouldStart(forced: false, now: start + 30)
        #expect(!answer7)
        let answer8 = schedule.shouldStart(forced: false, now: start + 31)
        #expect(answer8)
    }

    @Test func forcedRequestIgnoresTheInterval() {
        var schedule = IntegrationCheckSchedule()
        _ = schedule.shouldStart(forced: true, now: start)
        _ = schedule.finished(at: start + 1)

        let answer9 = schedule.shouldStart(forced: true, now: start + 2)
        #expect(answer9)
    }

    @Test func intervalCanBeShortened() {
        var schedule = IntegrationCheckSchedule(minimumInterval: 0)
        _ = schedule.shouldStart(forced: true, now: start)
        _ = schedule.finished(at: start + 1)

        let answer10 = schedule.shouldStart(forced: false, now: start + 1)
        #expect(answer10)
    }

    @Test func standardIntervalIsThirtySeconds() {
        #expect(IntegrationCheckSchedule.standardInterval == 30)
    }
}
