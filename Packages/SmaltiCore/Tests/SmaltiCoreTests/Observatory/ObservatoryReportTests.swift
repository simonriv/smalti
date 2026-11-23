import Foundation
import SmaltiCore
import Testing

@Suite("ObservatoryReport")
struct ObservatoryReportTests {
    private typealias F = ObservatoryFixtures
    private let now = F.date("2026-11-18 10:42")
    private let calendar = F.calendar()

    private func report(_ snapshot: ObservatorySnapshot, _ period: ObservatoryPeriod = .today, selection: String? = nil)
        -> ObservatoryReport
    {
        ObservatoryReport.make(snapshot, period: period, selection: selection, calendar: calendar)
    }

    @Test func sessionCrossingMidnightCountsOnlyTodayBuckets() {
        let session = F.session(
            "s",
            [
                F.turn("y", at: F.date("2026-11-17 23:59"), output: 7),
                F.turn("t", at: F.date("2026-11-18 00:01"), output: 5),
            ])

        let today = report(F.snapshot(sessions: [session], now: now))
        let week = report(F.snapshot(sessions: [session], now: now), .lastSevenDays)

        #expect(today.summary.output == 5)
        #expect(week.summary.output == 12)
    }

    @Test func summaryAddsInputCacheAndCost() {
        let session = F.session(
            "s",
            [
                .assistantTurn(
                    AssistantTurn(
                        messageID: "a", model: F.opus,
                        usage: F.usage(input: 250_000, output: 1_000_000, cacheRead: 750_000),
                        at: F.date("2026-11-18 09:00"), isSubagent: false))
            ])

        let summary = report(F.snapshot(sessions: [session], now: now)).summary

        #expect(summary.input == 1_000_000)
        #expect(summary.cacheShare == 75)
        #expect(abs(summary.cost.usd - (1 + 20 + 0.15)) < 0.000_001)
    }

    @Test func rowTotalsSumToSummary() {
        let first = F.session("a", [F.turn("1", at: F.date("2026-11-18 09:00"), output: 1_500)])
        let second = F.session("b", [F.turn("2", at: F.date("2026-11-18 09:10"), output: 2_500)])

        let result = report(F.snapshot(sessions: [first, second], now: now))

        #expect(result.rows.map(\.output).sorted() == ["1.5k", "2.5k"])
        #expect(result.summary.output == 4_000)
    }

    @Test func liveRowsFirstByStartThenStoppedByActivity() {
        let sessions = [
            F.session("oldLive", [F.turn("1", at: F.date("2026-11-18 08:00"))]),
            F.session("newLive", [F.turn("2", at: F.date("2026-11-18 09:00"))]),
            F.session("stoppedEarly", [F.turn("3", at: F.date("2026-11-18 06:00"))]),
            F.session("stoppedLate", [F.turn("4", at: F.date("2026-11-18 07:00"))]),
        ]
        let running = [
            F.running("oldLive", pid: 1, startedAt: F.date("2026-11-18 08:00")),
            F.running("newLive", pid: 2, startedAt: F.date("2026-11-18 09:00")),
        ]

        let ids = report(F.snapshot(sessions: sessions, running: running, now: now)).rows.map(\.id)

        #expect(ids == ["newLive", "oldLive", "stoppedLate", "stoppedEarly"])
    }

    @Test func stoppedSessionOutsidePeriodIsNotARow() {
        let old = F.session("old", [F.turn("1", at: F.date("2026-11-10 08:00"))])

        #expect(report(F.snapshot(sessions: [old], now: now)).rows.isEmpty)
        #expect(report(F.snapshot(sessions: [old], now: now), .lastThirtyDays).rows.count == 1)
    }

    @Test func subagentsNeverBecomeRows() {
        let session = F.session(
            "s",
            [
                F.turn("1", at: F.date("2026-11-18 09:00")),
                F.turn("2", at: F.date("2026-11-18 09:01"), model: F.haiku, subagent: true),
            ])

        #expect(report(F.snapshot(sessions: [session], now: now)).rows.count == 1)
    }

    @Test func peakIsHighestBucketPeakInPeriod() {
        let session = F.session(
            "s",
            [
                F.turn("1", at: F.date("2026-11-18 09:00"), output: 900),
                F.turn("2", at: F.date("2026-11-18 10:42"), output: 4_800),
            ])

        let peak = report(F.snapshot(sessions: [session], now: now)).summary.peak

        #expect(peak?.output == 4_800)
        #expect(peak?.at == F.date("2026-11-18 10:42"))
    }

    @Test func incompleteIndexMarksPeriodAsReading() {
        let snapshot = F.snapshot(sessions: [], now: now, indexedSince: F.date("2026-11-15 00:00"))

        #expect(report(snapshot).summary.isComplete)
        #expect(!report(snapshot, .lastSevenDays).summary.isComplete)
    }

    @Test func compactionFreedShareOfWindow() {
        let session = F.session(
            "s",
            [
                F.turn("1", at: F.date("2026-11-18 10:00")),
                .compacted(Compaction(at: F.date("2026-11-18 10:20"), preTokens: 967_809, postTokens: 57_813)),
            ])

        let detail = report(F.snapshot(sessions: [session], now: now)).detail

        #expect(detail?.compaction == "Compactación hace 22 min · liberó 91% del contexto")
    }

    @Test func noCompactionText() {
        let session = F.session("s", [F.turn("1", at: F.date("2026-11-18 10:00"))])

        #expect(report(F.snapshot(sessions: [session], now: now)).detail?.compaction == "Sin compactaciones")
    }

    @Test func errorRateAtFivePercentIsHigh() {
        let records: [TranscriptRecord] = (0..<20).flatMap { index -> [TranscriptRecord] in
            let at = F.date("2026-11-18 09:00").addingTimeInterval(Double(index))
            return [
                .toolStarted(ToolStart(id: "t\(index)", name: "Bash", input: [:], at: at)),
                .toolFinished(ToolFinish(id: "t\(index)", isError: index == 0, exitCode: 1, diff: nil, at: at)),
            ]
        }

        let row = report(F.snapshot(sessions: [F.session("s", records)], now: now)).rows.first

        #expect(row?.errorRate == 5)
        #expect(row?.isErrorRateHigh == true)
    }

    @Test func defaultSelectionIsFirstRow() {
        let sessions = [
            F.session("a", [F.turn("1", at: F.date("2026-11-18 09:00"))]),
            F.session("b", [F.turn("2", at: F.date("2026-11-18 10:00"))]),
        ]

        let result = report(F.snapshot(sessions: sessions, now: now))

        #expect(result.detail?.sessionID == result.rows.first?.id)
    }

    @Test func detailFollowsSelection() {
        let sessions = [
            F.session("a", [F.turn("1", at: F.date("2026-11-18 09:00"))]),
            F.session("b", [F.turn("2", at: F.date("2026-11-18 10:00"))]),
        ]

        #expect(report(F.snapshot(sessions: sessions, now: now), selection: "a").detail?.sessionID == "a")
    }

    @Test func detailHasSixtyMinuteSeries() {
        let session = F.session(
            "s",
            [
                F.turn("1", at: F.date("2026-11-18 10:41"), output: 300),
                F.turn("2", at: F.date("2026-11-18 09:30"), output: 999),
            ])

        let detail = report(F.snapshot(sessions: [session], now: now)).detail

        #expect(detail?.outputPerMinute.count == 60)
        #expect(detail?.outputPerMinute.last == 0)
        #expect(detail?.outputPerMinute[58] == 300)
        #expect(detail?.title == "Actividad · solen/api")
    }

    @Test func liveRowShowsLifetimeContextAndPid() {
        let start = F.date("2026-11-18 09:30")
        let session = F.session("s", [F.turn("1", at: F.date("2026-11-18 10:40"), input: 410_000)])

        let row = report(F.snapshot(sessions: [session], running: [F.running("s", startedAt: start)], now: now)).rows
            .first

        #expect(row?.lifetime == "1h 12m")
        #expect(row?.context == .percent(41))
        #expect(row?.pid == "48213")
        #expect(row?.agentModel == "Claude Code · opus")
    }

    @Test func stoppedRowShowsAgoAndDashes() {
        let session = F.session("s", [F.turn("1", at: F.date("2026-11-18 07:42"))])

        let row = report(F.snapshot(sessions: [session], now: now)).rows.first

        #expect(row?.lifetime == "hace 3h")
        #expect(row?.context == .unavailable)
        #expect(row?.pid == "—")
        #expect(row?.state == .stopped)
    }

    @Test func summaryCountsLiveStates() {
        let start = F.date("2026-11-18 10:00")
        let snapshot = F.snapshot(
            sessions: [],
            running: [
                F.running("a", pid: 1, status: "busy", startedAt: start),
                F.running("b", pid: 2, status: "busy", startedAt: start),
                F.running("c", pid: 3, status: "idle", startedAt: start),
            ],
            now: now)

        let summary = report(snapshot).summary

        #expect(summary.active == 3)
        #expect(summary.working == 2)
        #expect(summary.waiting == 1)
        #expect(summary.failed == 0)
    }

    @Test func tiesKeepAStableOrderById() {
        let start = F.date("2026-11-18 10:00")
        let running = ["c", "a", "b"].enumerated().map { F.running($1, pid: Int32($0 + 1), startedAt: start) }

        let ids = report(F.snapshot(sessions: [], running: running, now: now)).rows.map(\.id)

        #expect(ids == ["a", "b", "c"])
    }

    @Test func summaryDependsOnTheTimeZoneOfEachRefresh() {
        let session = F.session("s", [F.turn("1", at: F.date("2026-11-18 02:00"), output: 9)])
        let snapshot = F.snapshot(sessions: [session], now: F.date("2026-11-18 10:00"))
        let tokyo = F.calendar("Asia/Tokyo")

        let inBogota = ObservatoryReport.make(snapshot, period: .today, selection: nil, calendar: calendar)
        let inTokyo = ObservatoryReport.make(snapshot, period: .today, selection: nil, calendar: tokyo)

        #expect(inBogota.summary.output == 9)
        #expect(inTokyo.summary.output == 0)
    }

    @Test func liveSessionWithoutTurnsRowShowsZeros() {
        let row = report(F.snapshot(sessions: [], running: [F.running("fresh", startedAt: now)], now: now)).rows.first

        #expect(row?.input == "0")
        #expect(row?.output == "0")
        #expect(row?.agentModel == "Claude Code")
        #expect(row?.context == .unavailable)
        #expect(row?.errorRate == 0)
    }

    @Test func rowInputAddsEveryModel() {
        let session = F.session(
            "s",
            [
                F.turn("1", at: F.date("2026-11-18 09:00"), input: 1_000),
                F.turn("2", at: F.date("2026-11-18 09:01"), input: 500, model: F.haiku, subagent: true),
            ])

        let result = report(F.snapshot(sessions: [session], now: now))

        #expect(result.rows.first?.input == "1.5k")
        #expect(result.summary.input == 1_500)
    }
}
