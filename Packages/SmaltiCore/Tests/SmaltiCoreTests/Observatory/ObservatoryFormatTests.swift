import Foundation
import SmaltiCore
import Testing

@Suite("ObservatoryFormat")
struct ObservatoryFormatTests {
    static let counts: [(Int, String)] = [
        (0, "0"), (412, "412"), (999, "999"), (1_000, "1k"), (61_400, "61.4k"), (99_950, "100k"),
        (982_000, "982k"), (999_600, "1M"), (1_240_000, "1.24M"), (2_000_000, "2M"), (1_200_000, "1.2M"),
    ]

    @Test(arguments: counts)
    func countFormatsBoardExamples(value: Int, text: String) {
        #expect(ObservatoryFormat.count(value) == text)
    }

    static let lifetimes: [(Double, String)] = [(0, "0m"), (2040, "34m"), (4320, "1h 12m"), (7500, "2h 05m")]

    @Test(arguments: lifetimes)
    func lifetimePadsMinutesAfterHours(seconds: Double, text: String) {
        #expect(ObservatoryFormat.lifetime(seconds) == text)
    }

    static let agos: [(Double, String)] = [
        (1320, "hace 22 min"), (3540, "hace 59 min"), (3600, "hace 1h"), (10_800, "hace 3h"),
        (86_400, "hace 1 día"), (172_800, "hace 2 días"), (20, "hace 0 min"),
    ]

    @Test(arguments: agos)
    func agoSwitchesUnitsAtHourAndDay(seconds: Double, text: String) {
        #expect(ObservatoryFormat.ago(seconds) == text)
    }

    @Test func gigabytesAndMegabytes() {
        #expect(ObservatoryFormat.gigabytes(6_100_000_000) == "6.1 GB")
        #expect(ObservatoryFormat.gigabytes(274_000_000) == "274 MB")
    }

    @Test func memoryRoundsTotal() {
        #expect(ObservatoryFormat.memory(used: 11_200_000_000, total: 17_179_869_184) == "11.2 / 16 GB")
    }

    @Test func usdTwoDecimals() {
        #expect(ObservatoryFormat.usd(18.4) == "$18.40")
        #expect(ObservatoryFormat.usd(0) == "$0.00")
        #expect(ObservatoryFormat.usd(1234.567) == "$1234.57")
    }

    @Test func percentHasSign() {
        #expect(ObservatoryFormat.percent(41) == "41%")
    }

    @Test func clockUsesTimeZone() {
        let instant = Date(timeIntervalSince1970: 1_795_000_000)  // 2026-11-18 11:06:40 UTC
        let bogota = TimeZone(identifier: "America/Bogota") ?? .gmt

        #expect(ObservatoryFormat.clock(instant, timeZone: .gmt) == "11:06")
        #expect(ObservatoryFormat.clock(instant, timeZone: bogota) == "06:06")
    }
}
