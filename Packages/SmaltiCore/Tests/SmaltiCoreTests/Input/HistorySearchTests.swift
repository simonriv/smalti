import Foundation
import SmaltiCore
import Testing

@Suite("HistorySearch")
struct HistorySearchTests {
    private let index = HistoryIndex(
        entries: [
            historyEntry("swift format lint --strict -r App", in: "/repo", at: 10),
            historyEntry("swift test --package-path Packages/SmaltiCore", in: "/repo", at: 20),
            historyEntry("ls", in: "/other", at: 30),
            historyEntry("swift test --filter Spike", in: "/other", at: 40),
        ], limit: 100)

    @Test func searchRanksContiguousFirst() {
        let hits = HistorySearch.search("swi te", scope: .all, in: index)

        #expect(hits.first?.stats.command.hasPrefix("swift test") == true)
        #expect(!hits.map(\.stats.command).contains("ls"))
    }

    @Test func searchScopeDirectoryFiltersOthers() {
        let hits = HistorySearch.search("swift", scope: .directory("/repo"), in: index)

        #expect(
            Set(hits.map(\.stats.command)) == [
                "swift format lint --strict -r App", "swift test --package-path Packages/SmaltiCore",
            ])
    }

    @Test func searchTiesByRecency() {
        let hits = HistorySearch.search("swift test", scope: .all, in: index)

        #expect(
            hits.prefix(2).map(\.stats.command) == [
                "swift test --filter Spike", "swift test --package-path Packages/SmaltiCore",
            ])
    }

    @Test func emptyQueryListsByRecency() {
        let hits = HistorySearch.search("", scope: .all, in: index)

        #expect(hits.map(\.stats.command).first == "swift test --filter Spike")
        #expect(hits.count == 4)
    }

    @Test func searchReturnsMatchedRanges() {
        let hit = HistorySearch.search("swi te", scope: .all, in: index).first

        #expect(hit?.matched == [0..<3, 5..<8])
    }

    @Test func caseAndAccentsAreIgnored() {
        let accented = HistoryIndex(entries: [historyEntry("echo canción")], limit: 10)

        #expect(HistorySearch.search("CANCION", scope: .all, in: accented).count == 1)
    }

    private let bogota = { () -> Calendar in
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota") ?? .gmt
        return calendar
    }()

    private func date(_ text: String) -> Date {
        (try? Date(text, strategy: .iso8601)) ?? .distantPast
    }

    @Test func agoMinutes() {
        #expect(
            HistorySearch.ago(date("2026-11-23T15:00:00Z"), now: date("2026-11-23T15:04:30Z"), calendar: bogota)
                == "hace 4 min")
        #expect(
            HistorySearch.ago(date("2026-11-23T15:00:00Z"), now: date("2026-11-23T15:00:10Z"), calendar: bogota)
                == "hace 1 min")
    }

    @Test func agoHoursAcrossMidnight() {
        // 23:30 → 00:30 in Bogotá (UTC−5): one hour, not "ayer".
        #expect(
            HistorySearch.ago(date("2026-11-24T04:30:00Z"), now: date("2026-11-24T05:30:00Z"), calendar: bogota)
                == "hace 1 h")
    }

    @Test func agoYesterdayAfterADay() {
        #expect(
            HistorySearch.ago(date("2026-11-22T13:00:00Z"), now: date("2026-11-23T15:00:00Z"), calendar: bogota)
                == "ayer")
    }

    @Test func agoDaysAcrossMonthEnd() {
        #expect(
            HistorySearch.ago(date("2026-10-30T15:00:00Z"), now: date("2026-11-02T15:00:00Z"), calendar: bogota)
                == "hace 3 días")
    }
}
