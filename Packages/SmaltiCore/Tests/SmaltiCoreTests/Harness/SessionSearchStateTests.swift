import Foundation
import SmaltiCore
import Testing

@Suite("Session search state")
struct SessionSearchStateTests {
    private let now = Date(timeIntervalSince1970: 1_795_600_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func session(_ id: String, _ harness: HarnessID, hoursAgo: Double = 1, detail: String? = nil)
        -> HarnessSession
    {
        let date = now.addingTimeInterval(-hoursAgo * 3600)
        return HarnessSession(
            harness: harness, id: id, directory: "/Users/s/dev/solen", title: "T \(id)", createdAt: date,
            updatedAt: date, detail: detail)
    }

    @Test func chipsHaveNoGemini() {
        #expect(SessionSearchState.chips.map(\.title) == ["Todas", "Claude Code", "Codex", "Antigravity", "OpenCode"])
    }

    @Test func chipAndTextMakeTheQuery() {
        var state = SessionSearchState()
        state.selectChip(2)
        state.text = "rls"

        #expect(state.query == SessionQuery(harness: .codex, text: "rls"))
    }

    @Test func chipsCycleBothWays() {
        var state = SessionSearchState()
        state.previousChip()
        #expect(state.chipIndex == 4)
        state.nextChip()
        #expect(state.chipIndex == 0)
    }

    @Test func rowsNameHarnessProjectAndDetail() {
        var state = SessionSearchState()
        state.listing = SessionListing(
            sessions: [session("a", .claude, detail: "212k tokens"), session("b", .antigravity)], failures: [:])

        let rows = state.rows(now: now, calendar: utc)

        #expect(rows.map(\.detail) == ["Claude Code · solen · 212k tokens", "Antigravity · solen"])
        #expect(rows.map(\.title) == ["T a", "T b"])
    }

    @Test func selectionClampsAndFollowsTheList() {
        var state = SessionSearchState()
        state.listing = SessionListing(sessions: [session("a", .codex), session("b", .codex)], failures: [:])

        state.moveSelection(by: 5)
        #expect(state.selected?.id == "b")
        state.moveSelection(by: -9)
        #expect(state.selected?.id == "a")
        state.listing = SessionListing(sessions: [], failures: [:])
        #expect(state.selected == nil)
    }

    @Test func emptyTexts() {
        var state = SessionSearchState()
        state.listing = SessionListing(sessions: [], failures: [:])
        #expect(state.emptyText == "No hay sesiones de agentes en este Mac")
        state.text = "x"
        #expect(state.emptyText == "Sin sesiones que coincidan")
        state.listing = SessionListing(sessions: [session("a", .codex)], failures: [:])
        #expect(state.emptyText == nil)
    }

    @Test func failuresAreListedAsMessages() {
        var state = SessionSearchState()
        state.listing = SessionListing(
            sessions: [], failures: [.codex: .unknownSchema(harness: .codex, path: "/c", missing: "cwd")])

        #expect(state.failureMessages == ["No se pudo leer Codex: esquema desconocido (falta cwd)"])
    }
    @Test func changingChipSelectsTheTop() {
        var state = SessionSearchState()
        state.listing = SessionListing(sessions: [session("a", .codex), session("b", .codex)], failures: [:])
        state.moveSelection(by: 1)

        state.selectChip(1)

        #expect(state.selected?.id == "a")
    }

    @Test func selectByIDPicksThatSession() {
        var state = SessionSearchState()
        state.listing = SessionListing(
            sessions: [session("a", .codex), session("b", .codex), session("c", .codex)], failures: [:])

        state.select(id: "c")

        #expect(state.selected?.id == "c")
    }

    @Test func failuresAreListedByHarnessName() {
        var state = SessionSearchState()
        let codex = HarnessError.storeMissing(harness: .codex, path: "/c")
        let agy = HarnessError.storeMissing(harness: .antigravity, path: "/a")

        state.listing = SessionListing(sessions: [], failures: [.codex: codex, .antigravity: agy])

        #expect(state.failureMessages == [agy.message, codex.message])
    }

    @Test func lateListingKeepsTheSelectedSession() {
        var state = SessionSearchState()
        state.listing = SessionListing(sessions: [session("a", .codex), session("b", .codex)], failures: [:])
        state.moveSelection(by: 1)

        state.listing = SessionListing(
            sessions: [session("new", .claude, hoursAgo: 0.1), session("a", .codex), session("b", .codex)],
            failures: [:])

        #expect(state.selected?.id == "b")
    }

    @Test func goneSelectionGoesBackToTheTop() {
        var state = SessionSearchState()
        state.listing = SessionListing(sessions: [session("a", .codex), session("b", .codex)], failures: [:])
        state.moveSelection(by: 1)

        state.listing = SessionListing(sessions: [session("a", .codex)], failures: [:])

        #expect(state.selected?.id == "a")
    }

    @Test func typingSelectsTheTopMatch() {
        var state = SessionSearchState()
        state.listing = SessionListing(sessions: [session("a", .codex), session("b", .codex)], failures: [:])
        state.moveSelection(by: 1)

        state.text = "x"

        #expect(state.selected?.id == "a")
    }
}

@Suite("Relative day")
struct RelativeDayTests {
    private let now = Date(timeIntervalSince1970: 1_795_600_000)  // Wed 2026-11-25 09:46 UTC
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    @Test func labelsByDistance() {
        let day = 86_400.0
        #expect(RelativeDay.label(now.addingTimeInterval(-3600), now: now, calendar: utc) == "hoy")
        #expect(RelativeDay.label(now.addingTimeInterval(-day), now: now, calendar: utc) == "ayer")
        #expect(RelativeDay.label(now.addingTimeInterval(-6 * day), now: now, calendar: utc) == "jue")
        #expect(RelativeDay.label(now.addingTimeInterval(-2 * day), now: now, calendar: utc) == "lun")
        #expect(RelativeDay.label(now.addingTimeInterval(-7 * day), now: now, calendar: utc) == "18 nov")
        #expect(RelativeDay.label(now.addingTimeInterval(-60 * day), now: now, calendar: utc) == "26 sep")
    }
}

@Suite("Session search tokens")
struct SessionSearchTokensTests {
    @Test func obsidianMatchesTheBoard() {
        let tokens = Theme.obsidian.sessionSearch

        #expect(tokens.width == 420)
        #expect(tokens.fieldHeight == 34)
        #expect(tokens.chipText == RGBAColor(red: 0xae, green: 0xb3, blue: 0xbd, alpha: 1))
        #expect(tokens.fieldBorder == RGBAColor(red: 255, green: 255, blue: 255, alpha: 0.09))
        #expect(tokens.background.alpha == 0.55)
        #expect(tokens.selectedText == Theme.obsidian.text.title)
    }

    @Test func pillsHeaderAndGlyphFromTheBoard() {
        let tokens = Theme.obsidian.sessionSearch

        #expect(tokens.headerLetterSpacing == 0.06)
        #expect(tokens.fieldGlyphSize == 12)
        #expect(RGBAColor.clear.alpha == 0)
    }

    @Test func observatoryFilterChipsFromTheBoard() {
        let tokens = Theme.obsidian.observatoryFilter

        #expect(tokens.chipHeight == 26)
        #expect(tokens.chipPadding == 10)
        #expect(tokens.chipRadius == 7)
        #expect(tokens.chipGap == 10)
        #expect(tokens.separatorHeight == 18)
        #expect(tokens.inactiveText == Theme.obsidian.strip.inactiveText)
        #expect(tokens.chosenBorder == Theme.obsidian.focus.ring)
        #expect(tokens.chosenBackground == Theme.obsidian.focus.glow)
    }
}
