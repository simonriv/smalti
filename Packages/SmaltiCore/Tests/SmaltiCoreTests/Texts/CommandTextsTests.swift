import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Command texts")
struct CommandTextsTests {
    private let set: WorkspaceSet

    init() throws {
        let root = try WorkingDirectory(path: "/tmp")
        set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: root, layout: DwindleLayout()))
    }

    @Test func catalogsHaveBothLanguages() {
        #expect(TextCatalogAudit.problems(spanish: CommandTexts.spanish, english: CommandTexts.english).isEmpty)
        #expect(TextCatalogAudit.problems(spanish: MenuTexts.spanish, english: MenuTexts.english).isEmpty)
        #expect(
            TextCatalogAudit.problems(spanish: HelpTexts.spanish, english: HelpTexts.english, allowed: ["Smalti"])
                .isEmpty)
    }

    @Test func everyStandardCommandHasATitleInBothLanguages() {
        let palette = CommandCatalog.commands(
            for: CatalogState(workspaces: set), keymap: .standard, layouts: .standard, texts: .english)

        #expect(palette.allSatisfy { !SpanishMarkers.looksSpanish($0.title) && $0.title != $0.id.rawValue })
    }

    @Test func englishTitlesFollowMacOSConventions() {
        let titles = CommandTexts.english.titles

        #expect(titles[.windowNew] == "New Window")
        #expect(titles[.feedbackReport] == "Report a Problem or Idea…")
        #expect(titles[.updatesCheck] == "Check for Updates…")
        #expect(titles[.appSupport] == "Support Smalti…")
        #expect(titles[.helpWelcome] == "Welcome to Smalti")
        #expect(titles[.helpPrivacy] == "Open the Privacy Policy")
    }

    @Test func newCommandsHaveSpanishTitles() {
        #expect(CommandTexts.spanish.titles[.helpWelcome] == "Bienvenida a Smalti")
        #expect(CommandTexts.spanish.titles[.helpPrivacy] == "Abrir la política de privacidad")
    }

    @Test func approvalInEnglish() {
        let approval = PendingApproval(
            id: UUID(), pane: PaneID(),
            subject: ApprovalSubject(
                command: "terraform destroy", findings: [GuardFinding(rule: "x", environment: .undetermined)]),
            since: Date(), deadline: Date())
        let state = CatalogState(
            workspaces: set, pendingApprovals: [ApprovalEntry(approval: approval, workspace: "rizaria")])

        let titles = CommandCatalog.commands(for: state, keymap: .standard, layouts: .standard, texts: .english)
            .prefix(2).map(\.title)

        #expect(titles == ["Approve “terraform destroy” in rizaria", "Reject “terraform destroy” in rizaria"])
    }

    @Test func groupsInEnglish() {
        #expect(CommandTexts.english.groups[.approvals] == "Waiting for your approval")
        #expect(CommandTexts.english.groups[.panes] == "Panes")
    }

    @Test func savedLayoutInEnglish() throws {
        let name = try LayoutName("rizaria-full")
        let summary = NamedLayoutSummary(name: name, paneCount: 4, agentCount: 2)
        let state = CatalogState(workspaces: set, savedLayouts: [summary])

        let restore = CommandCatalog.commands(for: state, keymap: .standard, layouts: .standard, texts: .english)
            .first { $0.id == .layoutRestore(name) }

        #expect(restore?.title == "Restore Layout “rizaria-full”")
        #expect(restore?.subtitle == "— 4 panes, resumes 2 Claude sessions")
    }

    @Test func helpMenuOffersWelcomeAndPrivacy() {
        let bar = MenuModel.bar(
            keymap: .standard, commands: [], state: MenuState(workspaces: set, checked: []), texts: .spanish)
        let help = bar.menus.first { $0.id == .help }?.items.compactMap(\.command)

        #expect(help?.prefix(4) == [.helpShow, .helpWelcome, .helpDocs, .helpPrivacy])
    }

    @Test func englishMenuTitles() {
        let bar = MenuModel.bar(
            keymap: .standard, commands: [], state: MenuState(workspaces: set, checked: []), texts: .english)

        #expect(bar.menus.map(\.title) == ["Smalti", "File", "Edit", "View", "Window", "Help"])
        let all = bar.menus.flatMap(\.items).flattened.map(\.title).filter { !$0.isEmpty }
        #expect(all.filter { SpanishMarkers.looksSpanish($0) }.isEmpty)
    }

    @Test func privacyIsTheLastHelpSection() {
        let sections = HelpCatalog.sections(keymap: .standard, texts: .english)

        #expect(sections.last?.title == "Privacy")
        #expect(sections.last?.entries.last?.command == .helpPrivacy)
        #expect(sections.flatMap(\.entries).contains { $0.command == .helpWelcome })
        #expect(sections.flatMap(\.entries).filter { SpanishMarkers.looksSpanish($0.title) }.isEmpty)
    }

    @Test func spanishPrivacySection() {
        #expect(HelpCatalog.sections(keymap: .standard, texts: .spanish).last?.title == "Privacidad")
    }
}
