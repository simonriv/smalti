import Foundation
import SmaltiCore
import Testing

@Suite("Observatory filter")
struct ObservatoryFilterTests {
    private let now = ObservatoryFixtures.date("2026-11-18 12:00")

    private func opencode(
        _ id: String, model: String = "qwen3:4b", local: Bool = true, input: Int = 300, output: Int = 40
    )
        -> UsageRow
    {
        UsageRow(
            harness: .opencode, sessionID: id, directory: "/Users/simon/termotty", model: model, isLocal: local,
            input: input, output: output, startedAt: now.addingTimeInterval(-3600),
            updatedAt: now.addingTimeInterval(-600))
    }

    private func snapshot(usage: [UsageRow]) -> ObservatorySnapshot {
        let claude = ObservatoryFixtures.session(
            "claude-1", [ObservatoryFixtures.turn("m1", at: now.addingTimeInterval(-900), output: 100, input: 1000)])
        return ObservatoryFixtures.snapshot(sessions: [claude], now: now).adding(usage: usage)
    }

    private func report(_ filter: ObservatoryFilter, usage: [UsageRow]) -> ObservatoryReport {
        ObservatoryReport.make(
            snapshot(usage: usage),
            for: .init(
                period: .today, selection: nil, calendar: ObservatoryFixtures.calendar(), filter: filter, copy: .spanish
            ))
    }

    @Test func filtersCycleInTheBoardsOrder() {
        #expect(ObservatoryFilter.allCases.map { $0.title } == ["Todas", "Claude Code", "OpenCode", "Locales"])
        #expect(ObservatoryFilter.local.next == .all)
        #expect(ObservatoryFilter.all.next == .claude)
    }

    @Test func allShowsBothHarnesses() {
        #expect(Set(report(.all, usage: [opencode("oc-1")]).rows.map(\.id)) == ["claude-1", "oc-1"])
    }

    @Test func localFilterKeepsOnlyLocalModels() {
        let rows = report(.local, usage: [opencode("oc-1"), opencode("oc-2", model: "gpt-x", local: false)]).rows

        #expect(rows.map(\.id) == ["oc-1"])
    }

    @Test func claudeNeverLocal() {
        #expect(!report(.local, usage: []).rows.contains { $0.id == "claude-1" })
        #expect(report(.claude, usage: [opencode("oc-1")]).rows.map(\.id) == ["claude-1"])
    }

    @Test func summaryRecomputedForFilter() {
        let summary = report(.opencode, usage: [opencode("oc-1", input: 300, output: 40)]).summary

        #expect(summary.input == 300)
        #expect(summary.output == 40)
    }

    @Test func opencodeRowLabelMarksLocal() {
        let row = report(.opencode, usage: [opencode("oc-1")]).rows.first

        #expect(row?.agentModel == "OpenCode · qwen3:4b local")
        #expect(row?.label == "termotty")
        #expect(row?.state == .stopped)
        #expect(row?.pid == "—")
        #expect(row?.isErrorRateHigh == false)
        #expect(
            report(.opencode, usage: [opencode("oc-2", local: false)]).rows.first?.agentModel == "OpenCode · qwen3:4b")
    }

    @Test func opencodeOutsideThePeriodIsLeftOut() {
        let old = UsageRow(
            harness: .opencode, sessionID: "old", directory: "/w", model: nil, isLocal: true, input: 1, output: 1,
            startedAt: now.addingTimeInterval(-90_000), updatedAt: now.addingTimeInterval(-86_400))

        #expect(report(.opencode, usage: [old]).rows.isEmpty)
    }

    @Test func goneSelectionFallsBackToFirstRow() {
        let report = ObservatoryReport.make(
            snapshot(usage: [opencode("oc-1")]),
            for: .init(
                period: .today, selection: "gone", calendar: ObservatoryFixtures.calendar(), filter: .all,
                copy: .spanish))

        #expect(report.detail?.sessionID == "claude-1")
    }

    @Test func cacheShareCountsOpenCodeCacheReads() {
        let row = UsageRow(
            harness: .opencode, sessionID: "oc-1", directory: "/w", model: "qwen3:4b", isLocal: true, input: 300,
            output: 40, startedAt: now.addingTimeInterval(-3600), updatedAt: now.addingTimeInterval(-600),
            cacheRead: 100)

        #expect(report(.all, usage: [row]).summary.cacheShare == 8)
        #expect(report(.opencode, usage: [row]).summary.cacheShare == 33)
    }

    @Test func opencodeLifetimeIsADash() {
        #expect(report(.opencode, usage: [opencode("oc-1")]).rows.first?.lifetime == "—")
    }

    @Test func footerNamesOpenCode() {
        #expect(
            ObservatoryCopy.spanish.footnote
                == "Datos: hooks y transcripts de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado."
        )
    }
}
