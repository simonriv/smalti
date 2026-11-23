import Foundation
import SmaltiCore
import Testing

@Suite("ClosedAtPhrase")
struct ClosedAtPhraseTests {
    private let bogota = Self.calendar("America/Bogota")

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private func date(_ text: String, in calendar: Calendar) -> Date {
        let parts = text.split(whereSeparator: { "- :".contains($0) }).compactMap { Int($0) }
        let components = DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])
        return calendar.date(from: components) ?? .distantPast
    }

    private func phrase(_ closed: String, now: String) -> String {
        ClosedAtPhrase.text(
            closedAt: date(closed, in: bogota), now: date(now, in: bogota), calendar: bogota)
    }

    @Test func sameDayIsToday() {
        #expect(phrase("2026-11-22 18:05", now: "2026-11-22 21:00") == "hoy a las 18:05")
    }

    @Test func previousEveningIsLastNight() {
        #expect(phrase("2026-11-21 23:48", now: "2026-11-22 08:00") == "anoche a las 23:48")
    }

    @Test func exactlySixPmIsLastNight() {
        #expect(phrase("2026-11-21 18:00", now: "2026-11-22 08:00") == "anoche a las 18:00")
    }

    @Test func previousAfternoonIsYesterday() {
        #expect(phrase("2026-11-21 14:10", now: "2026-11-22 08:00") == "ayer a las 14:10")
    }

    @Test func olderDateUsesWeekdayAndDay() {
        #expect(phrase("2026-11-19 09:12", now: "2026-11-22 08:00") == "el jue 19 a las 09:12")
    }

    @Test func crossesMonthBoundary() {
        #expect(phrase("2026-11-30 22:00", now: "2026-12-01 07:30") == "anoche a las 22:00")
    }

    @Test func usesGivenTimeZone() {
        let utc = Self.calendar("UTC")
        let closed = date("2026-11-22 03:00", in: utc)  // 21-nov 22:00 in Bogotá
        let now = date("2026-11-22 13:00", in: utc)  // 22-nov 08:00 in Bogotá

        #expect(ClosedAtPhrase.text(closedAt: closed, now: now, calendar: utc) == "hoy a las 03:00")
        #expect(ClosedAtPhrase.text(closedAt: closed, now: now, calendar: bogota) == "anoche a las 22:00")
    }

    @Test func bannerFormatsDayMonthAndTime() {
        #expect(
            RestoreBanner.text(savedAt: date("2026-11-22 23:48", in: bogota), calendar: bogota)
                == "── restaurado · 22 nov 23:48 ──")
    }

    @Test func bannerPadsMinutes() {
        #expect(
            RestoreBanner.text(savedAt: date("2026-01-05 07:03", in: bogota), calendar: bogota)
                == "── restaurado · 5 ene 07:03 ──")
    }
}
