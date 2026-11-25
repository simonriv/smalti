import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

/// Intermediate review 2 of F7.5: one test per finding, written before its fix.
@MainActor
@Suite("Guard review 2 findings")
struct ReviewTwoFindingsTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let pane = PaneID()

    private func pending(_ id: UUID = UUID(), command: String = "terraform destroy") -> PendingApproval {
        PendingApproval(
            id: id, pane: pane,
            subject: ApprovalSubject(
                command: command, findings: [GuardFinding(rule: "terraform destroy", environment: .undetermined)]),
            since: t0, deadline: t0.addingTimeInterval(600))
    }

    private func request(_ command: String, log: ReplyLog) -> GuardRequest {
        let use = ToolUse(tool: "Bash", command: command, cwd: "/p")
        return GuardRequest(
            id: UUID(), pane: pane, use: use, environmentHosts: [],
            localVerdict: ScreenToolUse.verdict(
                for: use, context: GuardContext(settings: .standard, environmentHosts: []), home: "/Users/u"),
            receivedAt: t0, reply: { log.record($0) })
    }

    // MARK: - I1: never the home folder nor above it

    @Test(arguments: ["/Users/u", "/Users/u/", "/Users", "/"])
    func homeAndItsAncestorsCannotBeProtected(project: String) {
        let secrets = ProtectProjectSecrets(permissions: InMemoryProjectPermissions(), home: "/Users/u")

        #expect(!secrets.canProtect(project))
    }

    @Test(arguments: ["/Users/u/dev/rizaria", "/tmp/p", "/Users/uu"])
    func projectsBelowOrBesideHomeCanBeProtected(project: String) {
        #expect(ProtectProjectSecrets(permissions: InMemoryProjectPermissions(), home: "/Users/u").canProtect(project))
    }

    @Test func protectingHomeIsRefusedWithoutWriting() {
        let permissions = InMemoryProjectPermissions()
        let secrets = ProtectProjectSecrets(permissions: permissions, home: "/Users/u")

        #expect(throws: ProjectPermissionsError.self) { try secrets.protect("/Users/u") }
        #expect(permissions.writes == 0)
    }

    // MARK: - I2 and M7: the card's content

    @Test func sameApprovalAtAnotherMinuteKeepsTheCommand() {
        let approval = pending()
        let before = ApprovalCardContent(approval: approval, count: 1, workspace: "w", keys: .standard, now: t0)
        let after = ApprovalCardContent(
            approval: approval, count: 2, workspace: "w", keys: .standard, now: t0.addingTimeInterval(61))

        #expect(after.showsSameCommand(as: before))
        #expect(
            !after.showsSameCommand(
                as: ApprovalCardContent(approval: pending(), count: 1, workspace: "w", keys: .standard, now: t0)))
    }

    @Test func footerNamesTheKeys() {
        let content = ApprovalCardContent(approval: pending(), count: 1, workspace: "w", keys: .standard, now: t0)

        #expect(content.footer == "⇧⌘↩ aprobar   ⇧⌘⎋ rechazar   vence en 10 min")
        #expect(content.counter == "1 de 1")
    }

    @Test func unboundKeysFallBackToThePalette() throws {
        let keys = try Keymap.standard.overriding([
            try KeyChord.parse("cmd+shift+enter"): nil, try KeyChord.parse("cmd+shift+escape"): nil,
        ])
        let content = ApprovalCardContent(approval: pending(), count: 1, workspace: "w", keys: keys, now: t0)

        #expect(content.footer == "⌘K aprobar   ⌘K rechazar   vence en 10 min")
    }

    @Test func expiryNeverSaysZero() {
        let content = ApprovalCardContent(
            approval: pending(), count: 1, workspace: "w", keys: .standard, now: t0.addingTimeInterval(599))

        #expect(content.footer.hasSuffix("vence en 1 min"))
    }

    // MARK: - M1 and M2: the queue's answers

    @Test func expireReportsTheNextDeadlineEvenWhenNothingExpired() {
        let approvals = AgentApprovals(home: "/Users/u")
        approvals.receive(request("terraform destroy", log: ReplyLog()))

        let next = approvals.expire(now: t0.addingTimeInterval(-3_600))

        #expect(next == t0.addingTimeInterval(AgentApprovals.standardTimeout))
    }

    @Test func decidingAGoneApprovalSaysSo() {
        let approvals = AgentApprovals(home: "/Users/u")
        approvals.receive(request("terraform destroy", log: ReplyLog()))
        let id = approvals.allPending[0].id

        #expect(approvals.approve(id))
        #expect(!approvals.approve(id))
        #expect(!approvals.reject(id))
    }

    // MARK: - M9: contrast over the worst backdrop

    @Test(arguments: ThemeID.allCases)
    func cardTextKeeps4_5(_ id: ThemeID) {
        let theme = ThemeCatalog.theme(id)
        let card = theme.approvalCard
        let ground = id.worstBackdrop.color.underneath(theme.window.background).underneath(card.background)
        let commandGround = ground.underneath(card.commandBackground)

        #expect(ContrastRatio.between(ground, card.title) >= 4.5, "title on \(id)")
        #expect(ContrastRatio.between(ground, card.body) >= 4.5, "body on \(id)")
        #expect(ContrastRatio.between(ground, card.emphasis) >= 4.5, "emphasis on \(id)")
        #expect(ContrastRatio.between(commandGround, card.emphasis) >= 4.5, "command on \(id)")
    }
}
