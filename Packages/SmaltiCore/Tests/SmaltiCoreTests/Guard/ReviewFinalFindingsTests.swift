import Foundation
import SmaltiCoreTestSupport
import Testing

@testable import SmaltiCore

/// Final review of F7.5: one test per finding, written before its fix.
@MainActor
@Suite("Guard final review findings", .serialized)
struct ReviewFinalFindingsTests {
    private let home = "/Users/u"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let pane = PaneID()

    private func verdict(_ command: String) -> GuardVerdict {
        ScreenToolUse.verdict(
            for: ToolUse(tool: "Bash", command: command, cwd: "/p"),
            context: GuardContext(settings: .standard, environmentHosts: [], texts: .spanish), home: home)
    }

    private func subject(_ command: String, rule: String = "URL de base de datos") -> ApprovalSubject {
        ApprovalSubject(command: command, findings: [GuardFinding(rule: rule, environment: .undetermined)])
    }

    private func request(_ id: UUID = UUID(), command: String = "terraform destroy", at seconds: Double = 0)
        -> GuardRequest
    {
        GuardRequest(
            id: id, pane: pane, use: ToolUse(tool: "Bash", command: command, cwd: "/p"), environmentHosts: [],
            localVerdict: .ask(ApprovalSubject(command: "", findings: [])),
            receivedAt: t0.addingTimeInterval(seconds), reply: { _ in })
    }

    // MARK: - I1: other tools of the same pane keep it waiting

    @Test(arguments: [AgentHook.preToolUse, .postToolUse, .notification])
    func approvalWaitSurvivesOtherToolEvents(hook: AgentHook) {
        let session = AgentSession(harness: .claude, sessionID: "s1", title: nil, state: .working, startedAt: t0)
        let waiting = session.awaitingApproval(subject("terraform destroy", rule: "terraform destroy"), at: t0).session

        let next = waiting.applying(
            AgentEvent(pane: pane, hook: hook, at: t0.addingTimeInterval(5), sessionID: "s1", message: "m"))

        #expect(next.session.state == waiting.state)
    }

    @Test func stopStillEndsTheTurn() {
        let session = AgentSession(harness: .claude, sessionID: "s1", title: nil, state: .working, startedAt: t0)
        let waiting = session.awaitingApproval(subject("terraform destroy"), at: t0).session

        let next = waiting.applying(AgentEvent(pane: pane, hook: .stop, at: t0, sessionID: "s1"))

        #expect(next.session.state == .waiting(since: t0, reason: .turnFinished))
    }

    // MARK: - I2: a cancelled hook takes its request away

    @Test func cancelledRequestLeavesTheQueue() {
        let approvals = AgentApprovals(home: home, texts: .spanish)
        var changes: [AgentApprovalChange] = []
        approvals.onChange = { changes.append($0) }
        let id = UUID()
        approvals.receive(request(id))

        approvals.cancel(id)

        #expect(approvals.allPending.isEmpty)
        #expect(changes.last.map { if case .settled(_, false, 0) = $0 { true } else { false } } == true)
    }

    @Test func cancellingTwiceOrUnknownDoesNothing() {
        let approvals = AgentApprovals(home: home, texts: .spanish)
        approvals.receive(request())

        approvals.cancel(UUID())

        #expect(approvals.allPending.count == 1)
    }

    // MARK: - I3: env files whose values would show

    @Test(arguments: [
        "node --env-file=.env -pe \"process.env\"", "deno eval --env-file=.env \"console.log(Deno.env.toObject())\"",
        "docker run --env-file .env alpine env", "docker compose --env-file .env run api printenv",
        "docker compose --env-file .env exec api env", "bun --env-file .env -e \"console.log(process.env)\"",
        "node --env-file=.env <<EOF\nconsole.log(process.env)\nEOF",
    ])
    func envFilesThatPrintAreDenied(command: String) {
        #expect(verdict(command).isDenied)
    }

    @Test(arguments: [
        "docker compose --env-file .env up -d", "docker compose --env-file .env build",
        "node --env-file=.env server.js",
    ])
    func envFilesThatOnlyRunStillPass(command: String) {
        #expect(verdict(command) == .allow)
    }

    // MARK: - M1: every host of a URL, and `?host=`

    @Test func hostParameterOfASocketURL() {
        #expect(DatabaseURL.hosts(in: "postgresql:///postgres?host=db.abc.supabase.co") == ["db.abc.supabase.co"])
    }

    @Test func everyHostOfAList() {
        #expect(DatabaseURL.hosts(in: "postgres://localhost,prod.host/db") == ["localhost", "prod.host"])
    }

    @Test func remoteHostParameterTriggersTheURLRule() {
        #expect(
            guardFindings("node seed.js postgresql:///app?host=prod.example.com").map(\.rule) == [
                "URL de base de datos"
            ])
    }

    // MARK: - M2: a second key press right after the card changed does nothing

    @Test func approvingRightAfterTheCardChangedIsTooSoon() {
        let approvals = AgentApprovals(home: home, texts: .spanish)
        approvals.receive(request(command: "terraform destroy"))
        approvals.receive(request(command: "supabase db push", at: 1))

        let first = approvals.approveOldest(in: pane, now: t0.addingTimeInterval(10))
        let second = approvals.approveOldest(in: pane, now: t0.addingTimeInterval(10.1))
        let third = approvals.approveOldest(in: pane, now: t0.addingTimeInterval(10.6))

        #expect(first == .decided)
        #expect(second == .tooSoon)
        #expect(third == .decided)
    }

    @Test func emptyPaneHasNothingWaiting() {
        #expect(AgentApprovals(home: home, texts: .spanish).rejectOldest(in: pane, now: t0) == .nothingWaiting)
    }

    // MARK: - M3: the notification and ⌘K show the command

    @Test func noticeQuotesTheCommand() {
        let session = AgentSession(harness: .claude, sessionID: "s1", title: nil, state: .working, startedAt: t0)

        let attention = session.awaitingApproval(subject("node seed.js postgres://u@db.x.com/a"), at: t0).attention

        #expect(attention == .approval(command: "node seed.js postgres://u@db.x.com/a", environment: .production))
    }

    @Test func longCommandsAreFullInThePaletteSubtitle() throws {
        let root = try WorkingDirectory(path: "/tmp/p")
        let set = WorkspaceSet(
            first: Workspace.empty(name: "w", rootDirectory: root, layout: DwindleLayout())
                .adding(Pane(id: pane, workingDirectory: root)))
        let command = String(repeating: "x", count: 50) + " && terraform destroy"
        let approval = PendingApproval(
            id: UUID(), pane: pane, subject: subject(command, rule: "terraform destroy"), since: t0, deadline: t0)
        let state = CatalogState(workspaces: set, pendingApprovals: [ApprovalEntry(approval: approval, workspace: "w")])

        let entry = CommandCatalog.commands(for: state, keymap: .standard, layouts: .standard, texts: .spanish).first

        #expect(entry?.subtitle?.contains("&& terraform destroy") == true)
    }

    // MARK: - M4: the deny rules cover what the guard calls secret

    @Test func denyRulesCoverProjectDotFilesAndKeys() {
        let rules = SecretDenyRules.rules(home: home)

        for name in [
            ".npmrc", ".pypirc", ".netrc", ".pgpass", "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", ".env.preview",
        ] {
            #expect(rules.contains("Read(**/\(name))"), "\(name)")
        }
    }

    // MARK: - M5: passwords with `@`

    @Test func passwordWithAtIsHiddenWhole() {
        #expect(CommandRedaction.redacted("psql postgres://u:p@ss@host/db") == "psql postgres://u:•••@host/db")
        #expect(CommandRedaction.redacted("psql postgres://u:pa/ss@h/db") == "psql postgres://u:•••@h/db")
    }
}
