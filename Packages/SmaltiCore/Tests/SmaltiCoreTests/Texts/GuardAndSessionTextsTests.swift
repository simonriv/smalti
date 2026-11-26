import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Guard, terminal and session texts")
struct GuardAndSessionTextsTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func catalogsHaveBothLanguages() {
        #expect(
            TextCatalogAudit.problems(spanish: GuardTexts.spanish, english: GuardTexts.english, allowed: ["PROD"])
                .isEmpty)
        #expect(TextCatalogAudit.problems(spanish: TerminalTexts.spanish, english: TerminalTexts.english).isEmpty)
        #expect(TextCatalogAudit.problems(spanish: SessionTexts.spanish, english: SessionTexts.english).isEmpty)
    }

    private func context(_ texts: GuardTexts) -> GuardContext {
        GuardContext(settings: .standard, environmentHosts: [], texts: texts)
    }

    @Test func secretDenialSpeaksTheCLIsLanguage() {
        let use = ToolUse(tool: "Read", filePath: "/p/.env", cwd: "/p")

        let verdict = ScreenToolUse.verdict(for: use, context: context(.english), home: "/Users/x")

        guard case .deny(let denial) = verdict else {
            Issue.record("expected a denial")
            return
        }
        #expect(denial.reason.hasPrefix("Smalti blocks reading secret files (/p/.env)."))
    }

    @Test func destructiveRuleIsNamedInEnglish() {
        let use = ToolUse(
            tool: "Bash", command: "psql -c 'DROP TABLE users' postgres://u@db.example.com/app", cwd: "/p")

        let verdict = ScreenToolUse.verdict(for: use, context: context(.english), home: "/Users/x")

        guard case .ask(let subject) = verdict else {
            Issue.record("expected an approval")
            return
        }
        #expect(subject.headline?.rule == "psql with DROP")
        #expect(subject.summary(.english) == "psql with DROP against PROD")
    }

    @Test func approvalCardInEnglish() {
        let approval = PendingApproval(
            id: UUID(), pane: PaneID(),
            subject: ApprovalSubject(command: "x", findings: [GuardFinding(rule: "x", environment: .undetermined)]),
            since: t0, deadline: t0.addingTimeInterval(300))

        let card = ApprovalCardContent(
            approval: approval, count: 3, workspace: "web", keys: .standard, now: t0, texts: .english)

        #expect(card.counter == "1 of 3")
        #expect(card.footer == "⇧⌘↩ approve   ⇧⌘⎋ reject   expires in 5 min")
    }

    @Test func rejectionReasonInEnglish() {
        let subject = ApprovalSubject(
            command: "terraform destroy",
            findings: [GuardFinding(rule: "terraform destroy", environment: .undetermined)])

        #expect(
            GuardReasons.rejected(subject, texts: .english)
                == "The user rejected this command in Smalti (terraform destroy, against PROD). Don’t retry it or look for another way; ask what to do."
        )
    }

    @Test func closeQuestionInEnglish() {
        let busy = [BusyPane(pane: PaneID(), command: "npm run dev")]

        let question = CloseGuard.question(
            for: .quit(windowCount: 2), busy: busy, settings: WindowSettings(confirmClose: true), texts: .english)

        #expect(question?.title == "Quit Smalti?")
        #expect(
            question?.detail
                == "1 process still running in 2 windows. When you come back you can pick them up from Resume.")
    }

    @Test func searchProgressInEnglish() {
        #expect(SearchProgress().total(0).progress.text(.english) == "No results")
        #expect(SearchProgress().total(12).progress.text(.english) == "– of 12")
    }

    @Test func thousandsAreGroupedPerLanguage() {
        #expect(ResumeListing.grouped(1_240, separator: SessionTexts.english.thousandsSeparator) == "1,240")
        #expect(ResumeListing.grouped(1_240, separator: SessionTexts.spanish.thousandsSeparator) == "1.240")
    }

    @Test func sharedLayoutErrorsInEnglish() {
        #expect(SharedLayoutError.paneCount(0).message(SessionTexts.english.layoutErrors) == "it has no panes")
        #expect(
            LayoutShareError.archive(.notFound(name: "web")).message(.english) == "no layout is saved as “web”")
    }

    @Test func relativeDayInEnglish() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let old = t0.addingTimeInterval(-20 * 86_400)

        #expect(RelativeDay.label(t0, now: t0, calendar: calendar, texts: .english) == "today")
        #expect(RelativeDay.label(old, now: t0, calendar: calendar, texts: .english).hasPrefix("Dec"))
    }

    @MainActor @Test func automaticUpdatesToggleInEnglish() {
        let updates = FakeAppUpdates(isAutomatic: true)

        #expect(SetAutomaticUpdates(updates: updates, texts: .english).toggle() == "Automatic updates turned off")
    }
}

@Suite("Session search token counts")
struct SessionSearchTokenCountTests {
    @Test func tokensAreWrittenInTheInterfacesLanguage() throws {
        var session = HarnessSession(
            harness: .codex, id: "a", directory: "/p/web", title: "t", createdAt: .distantPast, updatedAt: .distantPast,
            detail: "ollama")
        session.tokens = 4_439
        var state = SessionSearchState()
        state.listing = SessionListing(sessions: [session], failures: [:])
        let calendar = Calendar(identifier: .gregorian)

        #expect(
            state.rows(now: .distantPast, calendar: calendar, texts: .spanish).first?.detail
                == "Codex · web · ollama · 4.439 tokens")
        #expect(
            state.rows(now: .distantPast, calendar: calendar, texts: .english).first?.detail
                == "Codex · web · ollama · 4,439 tokens")
    }
}
