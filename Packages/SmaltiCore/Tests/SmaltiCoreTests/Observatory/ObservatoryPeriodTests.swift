import Foundation
import SmaltiCore
import Testing

@Suite("ObservatoryPeriod")
struct ObservatoryPeriodTests {
    private typealias F = ObservatoryFixtures

    @Test func todayStartsAtLocalMidnight() {
        let calendar = F.calendar()

        #expect(
            ObservatoryPeriod.today.start(now: F.date("2026-11-18 10:42"), calendar: calendar)
                == F.date("2026-11-18 00:00"))
    }

    @Test func sevenDaysStartsSixMidnightsAgo() {
        let start = ObservatoryPeriod.lastSevenDays.start(now: F.date("2026-11-18 10:42"), calendar: F.calendar())

        #expect(start == F.date("2026-11-12 00:00"))
    }

    @Test func thirtyDaysCrossesMonthEnd() {
        let start = ObservatoryPeriod.lastThirtyDays.start(now: F.date("2026-12-05 08:00"), calendar: F.calendar())

        #expect(start == F.date("2026-11-06 00:00"))
    }

    @Test func dstDayInNewYorkStartsAtLocalMidnight() {
        let newYork = F.calendar("America/New_York")
        let now = F.date("2026-11-01 12:00", newYork)  // DST ends at 02:00 that day

        #expect(ObservatoryPeriod.today.start(now: now, calendar: newYork) == F.date("2026-11-01 00:00", newYork))
        #expect(
            ObservatoryPeriod.lastSevenDays.start(now: now, calendar: newYork) == F.date("2026-10-26 00:00", newYork))
    }

    @Test func periodUsesCurrentTimeZoneEachTime() {
        let now = F.date("2026-11-18 03:00")  // 08:00 UTC

        let bogota = ObservatoryPeriod.today.start(now: now, calendar: F.calendar())
        let utc = ObservatoryPeriod.today.start(now: now, calendar: F.calendar("UTC"))

        #expect(bogota != utc)
    }

    @Test func nextCyclesThroughPeriods() {
        #expect(ObservatoryPeriod.today.next == .lastSevenDays)
        #expect(ObservatoryPeriod.lastSevenDays.next == .lastThirtyDays)
        #expect(ObservatoryPeriod.lastThirtyDays.next == .today)
    }

    @Test func titlesComeFromTheBoard() {
        #expect(ObservatoryPeriod.allCases.map { $0.title(copy: .spanish) } == ["Hoy", "7 días", "30 días"])
    }
}
