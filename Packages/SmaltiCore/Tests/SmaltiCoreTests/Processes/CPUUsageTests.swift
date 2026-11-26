import Foundation
import SmaltiCore
import Testing

@Suite("CPUUsage")
struct CPUUsageTests {
    private typealias F = ProcessFixtures

    @Test func percentIsCPUTimeOverWallTime() {
        let before = F.sample([F.record(10, cpuTime: 0)], at: 10)
        let after = F.sample([F.record(10, cpuTime: F.second / 2)], at: 11)

        let usage = CPUUsage.percentages(previous: before, current: after)

        #expect(usage[ProcessIdentity(pid: 10, startedAt: F.start)] == 50)
    }

    @Test func moreThanOneCoreGoesOverAHundred() {
        let before = F.sample([F.record(10, cpuTime: 0)], at: 10)
        let after = F.sample([F.record(10, cpuTime: 3 * F.second)], at: 12)

        let usage = CPUUsage.percentages(previous: before, current: after)

        #expect(usage[ProcessIdentity(pid: 10, startedAt: F.start)] == 150)
    }

    @Test func noPreviousSampleGivesNothing() {
        let usage = CPUUsage.percentages(previous: nil, current: F.sample([F.record(10, cpuTime: 5)]))

        #expect(usage.isEmpty)
    }

    @Test func reusedPIDStartsOver() {
        let later = F.start.addingTimeInterval(5)
        let before = F.sample([F.record(10, cpuTime: 0)], at: 10)
        let after = F.sample([F.record(10, cpuTime: F.second, startedAt: later)], at: 11)

        let usage = CPUUsage.percentages(previous: before, current: after)

        #expect(usage.isEmpty)
    }

    @Test func noElapsedTimeGivesNothing() {
        let before = F.sample([F.record(10, cpuTime: 0)], at: 10)
        let after = F.sample([F.record(10, cpuTime: F.second)], at: 10)

        #expect(CPUUsage.percentages(previous: before, current: after).isEmpty)
    }

    @Test func cpuTimeGoingBackIsZero() {
        let before = F.sample([F.record(10, cpuTime: F.second)], at: 10)
        let after = F.sample([F.record(10, cpuTime: 0)], at: 11)

        #expect(
            CPUUsage.percentages(previous: before, current: after)[ProcessIdentity(pid: 10, startedAt: F.start)] == 0)
    }
}
