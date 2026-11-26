import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@MainActor
@Suite("Approval state")
struct ApprovalStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ state: AgentState = .working) -> AgentSession {
        AgentSession(harness: .claude, sessionID: "s1", title: nil, state: state, startedAt: t0)
    }

    private let subject = ApprovalSubject(
        command: "supabase db push",
        findings: [GuardFinding(rule: "supabase db push", environment: .undetermined)])

    @Test func awaitingApprovalWaitsAndAsksForAttention() {
        let transition = session().awaitingApproval(subject, at: t0)

        #expect(transition.session.state == .waiting(since: t0, reason: .approval(subject)))
        #expect(transition.attention == .approval(command: "supabase db push", environment: .production))
    }

    @Test func settledApprovalWorksAgain() {
        let waiting = session().awaitingApproval(subject, at: t0).session

        #expect(waiting.approvalSettled().state == .working)
    }

    @Test func settlingDoesNotTouchOtherWaits() {
        let finished = session(.waiting(since: t0, reason: .turnFinished))

        #expect(finished.approvalSettled() == finished)
    }

    @Test func noticeNamesCommandAndEnvironment() {
        let notice = AttentionNotice.make(
            .approval(command: "supabase db push", environment: .production),
            at: ("rizaria", SessionFixtures.directory("/p/web"), PaneID()), texts: .spanish)

        #expect(notice.title == "rizaria/web")
        #expect(notice.body == "Aprobación: `supabase db push` contra PROD")
    }

    @Test func approvalAlwaysNotifies() {
        #expect(AttentionPolicy.shouldNotify(.approval(command: "x", environment: .production), paneIsVisible: true))
    }

    @Test func headerSaysItWaitsForApproval() throws {
        var set = agentSet()
        let pane = set.active.panes[0].id
        let pending = PendingApproval(id: UUID(), pane: pane, subject: subject, since: t0, deadline: t0)
        HandleApprovalChange(notifier: RecordingNotifier(), texts: .spanish).execute(.waiting(pending), in: &set)

        let content = PaneHeaderContent(
            set.active.panes[0], index: 1,
            context: HeaderContext(
                keymap: .standard, home: try WorkingDirectory(path: "/Users/s"), now: t0.addingTimeInterval(125),
                texts: .spanish))

        #expect(content.detail == HeaderDetail(text: "espera tu aprobación · 2m", tone: .waiting))
    }

    /// One workspace with one pane whose agent is working.
    private func agentSet(withAgent: Bool = true) -> WorkspaceSet {
        let pane = Pane(id: PaneID(), workingDirectory: SessionFixtures.directory("/p/web"))
        let workspace = Workspace.empty(
            name: "rizaria", rootDirectory: SessionFixtures.directory("/p"), layout: DwindleLayout()
        ).adding(pane)
        let set = WorkspaceSet(first: workspace)
        guard withAgent else { return set }
        return set.updating(set.activeID) {
            $0.applying(AgentEvent(pane: pane.id, hook: .preToolUse, at: t0, sessionID: "s1")).0
        }
    }

    @Test func handleApprovalUpdatesThePaneAndNotifies() {
        let notifier = RecordingNotifier()
        var set = agentSet()
        let pane = set.active.panes[0].id
        let pending = PendingApproval(id: UUID(), pane: pane, subject: subject, since: t0, deadline: t0)

        HandleApprovalChange(notifier: notifier, texts: .spanish).execute(.waiting(pending), in: &set)

        #expect(set.active.panes[0].agent?.state.kind == .waiting)
        #expect(notifier.delivered.map(\.body) == ["Aprobación: `supabase db push` contra PROD"])

        HandleApprovalChange(notifier: notifier, texts: .spanish).execute(
            .settled(pending, approved: true, remaining: 0), in: &set)
        #expect(set.active.panes[0].agent?.state == .working)
    }

    @Test func settledWithOthersLeftKeepsWaiting() {
        var set = agentSet()
        let pane = set.active.panes[0].id
        let pending = PendingApproval(id: UUID(), pane: pane, subject: subject, since: t0, deadline: t0)
        let handle = HandleApprovalChange(notifier: RecordingNotifier(), texts: .spanish)
        handle.execute(.waiting(pending), in: &set)

        handle.execute(.settled(pending, approved: false, remaining: 1), in: &set)

        #expect(set.active.panes[0].agent?.state.kind == .waiting)
    }

    @Test func paneWithoutAgentStillNotifies() {
        let notifier = RecordingNotifier()
        var set = agentSet(withAgent: false)
        let pending = PendingApproval(
            id: UUID(), pane: set.active.panes[0].id, subject: subject, since: t0, deadline: t0)

        HandleApprovalChange(notifier: notifier, texts: .spanish).execute(.waiting(pending), in: &set)

        #expect(notifier.delivered.count == 1)
        #expect(set.active.panes[0].agent == nil)
    }
}
