import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Status and observatory texts")
struct StatusAndObservatoryTextsTests {
    @Test func catalogsHaveBothLanguages() {
        #expect(TextCatalogAudit.problems(spanish: ObservatoryCopy.spanish, english: ObservatoryCopy.english).isEmpty)
        #expect(TextCatalogAudit.problems(spanish: StatusTexts.spanish, english: StatusTexts.english).isEmpty)
        #expect(TextCatalogAudit.problems(spanish: TimeTexts.spanish, english: TimeTexts.english).isEmpty)
    }

    @Test func agoInEnglish() {
        #expect(ObservatoryFormat.ago(22 * 60, texts: .english) == "22 min ago")
        #expect(ObservatoryFormat.ago(3 * 3600, texts: .english) == "3h ago")
        #expect(ObservatoryFormat.ago(86_400, texts: .english) == "1 day ago")
        #expect(ObservatoryFormat.ago(2 * 86_400, texts: .english) == "2 days ago")
        #expect(ObservatoryFormat.agoCompact(22 * 60, texts: .english) == "22m ago")
    }

    @Test func elapsedPhraseInEnglish() {
        let now = Date()

        #expect(ElapsedPhrase.text(since: now.addingTimeInterval(-30), now: now, texts: .english) == "now")
        #expect(ElapsedPhrase.text(since: now.addingTimeInterval(-120), now: now, texts: .english) == "2 min ago")
    }

    @Test func statusLineInEnglish() throws {
        let root = try WorkingDirectory(path: "/tmp")
        let one = Workspace.empty(name: "solen", rootDirectory: root, layout: ColumnsLayout())
            .adding(Pane(id: PaneID(), workingDirectory: root))
        let three = one.adding(Pane(id: PaneID(), workingDirectory: root)).adding(
            Pane(id: PaneID(), workingDirectory: root))

        #expect(one.statusLine(texts: .english) == "solen · 1 pane · columns")
        #expect(three.statusLine(texts: .english) == "solen · 3 panes · columns")
        #expect(three.statusLine(texts: .spanish) == "solen · 3 paneles · columnas")
    }

    @Test func telemetryInEnglishUsesThePoint() {
        #expect(TelemetryTexts.duration(milliseconds: 1_420, copy: .english) == "1.4 s")
        #expect(TelemetryTexts.duration(milliseconds: 1_420, copy: .spanish) == "1,4 s")
    }

    @Test func periodsInEnglish() {
        #expect(ObservatoryPeriod.allCases.map { $0.title(copy: .english) } == ["Today", "7 days", "30 days"])
    }

    @Test func stripCountersInEnglish() {
        let counters = StripCounter.counters(AgentCounts(working: 2, waiting: 1, failed: 0), texts: .english)

        #expect(counters.map(\.text) == ["2 working", "1 waiting"])
    }

    @Test func closedAtInEnglish() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Bogota"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 9)))
        let lastNight = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 23, minute: 48)))
        let thursday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9, minute: 12)))

        #expect(
            ClosedAtPhrase.text(closedAt: lastNight, now: now, calendar: calendar, texts: .english)
                == "last night at 23:48")
        #expect(
            ClosedAtPhrase.text(closedAt: thursday, now: now, calendar: calendar, texts: .english)
                == "on Thu 19 at 09:12")
    }
}

/// F7.7 (found by the UI walk): the Observatory's harness chips.
@Suite("Observatory filter titles")
struct ObservatoryFilterTitleTests {
    @Test func chipsInBothLanguages() {
        #expect(
            ObservatoryFilter.allCases.map { $0.title(.spanish) } == ["Todas", "Claude Code", "OpenCode", "Locales"])
        #expect(ObservatoryFilter.allCases.map { $0.title(.english) } == ["All", "Claude Code", "OpenCode", "Local"])
    }
}
