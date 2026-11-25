import Foundation
import SmaltiCore
import Synchronization
import Testing

/// Collects the decisions a request receives.
final class ReplyLog: Sendable {
    private let decisions = Mutex<[GuardDecision]>([])

    var all: [GuardDecision] { decisions.withLock { $0 } }

    func record(_ decision: GuardDecision) {
        decisions.withLock { $0.append(decision) }
    }
}

@MainActor
@Suite("Agent approvals")
struct AgentApprovalsTests {
    private let pane = PaneID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(
        _ command: String, pane: PaneID? = nil, local: GuardVerdict? = nil, hosts: [String] = [],
        at seconds: Double = 0,
        log: ReplyLog
    ) -> GuardRequest {
        let use = ToolUse(tool: "Bash", command: command, cwd: "/p")
        let verdict =
            local
            ?? ScreenToolUse.verdict(
                for: use, context: GuardContext(settings: .standard, environmentHosts: hosts), home: "/Users/u")
        return GuardRequest(
            id: UUID(), pane: pane ?? self.pane, use: use, environmentHosts: hosts, localVerdict: verdict,
            receivedAt: t0.addingTimeInterval(seconds), reply: { log.record($0) })
    }

    private func approvals(_ changes: ChangeLog = ChangeLog()) -> AgentApprovals {
        let approvals = AgentApprovals(home: "/Users/u")
        approvals.onChange = { changes.items.append($0) }
        return approvals
    }

    final class ChangeLog {
        var items: [AgentApprovalChange] = []
    }

    @Test func localDenyIsRepliedAtOnce() {
        let log = ReplyLog()
        let approvals = approvals()
        let denial = GuardDenial(kind: .secret(path: ".env"), reason: "r")

        approvals.receive(request("git status", local: .deny(denial), log: log))

        #expect(log.all == [.deny("r")])
        #expect(approvals.allPending.isEmpty)
    }

    @Test func innocentIsAllowedAtOnce() {
        let log = ReplyLog()
        let approvals = approvals()

        approvals.receive(request("git status", log: log))

        #expect(log.all == [.allow])
    }

    @Test func appSettingsRelaxURLRule() {
        let log = ReplyLog()
        let approvals = approvals()
        approvals.settings.nonProductionHosts = ["db.qa.example.com"]

        approvals.receive(request("node seed.js postgres://u@db.qa.example.com/x", log: log))

        #expect(log.all == [.allow])
    }

    @Test func appSettingsAddProviderHosts() {
        let log = ReplyLog()
        let approvals = approvals()
        approvals.settings.providerAPIHosts = ["api.example-cloud.com"]

        approvals.receive(request("curl -X DELETE https://api.example-cloud.com/x", log: log))

        #expect(log.all.isEmpty)
        #expect(approvals.pending(in: pane).count == 1)
    }

    @Test func askQueuesAndNotifies() {
        let log = ReplyLog()
        let changes = ChangeLog()
        let approvals = approvals(changes)

        approvals.receive(request(IncidentCommands.dataTalks, log: log))

        #expect(log.all.isEmpty)
        let pending = approvals.pending(in: pane)
        #expect(pending.map(\.subject.summary) == ["terraform destroy contra PROD"])
        #expect(pending.first?.deadline == t0.addingTimeInterval(AgentApprovals.standardTimeout))
        #expect(changes.items == [.waiting(pending[0])])
    }

    @Test func approveResolvesOnlyTheOldest() {
        let first = ReplyLog()
        let second = ReplyLog()
        let changes = ChangeLog()
        let approvals = approvals(changes)
        approvals.receive(request("terraform destroy", log: first))
        approvals.receive(request("supabase db push", at: 1, log: second))

        let didApprove = approvals.approveOldest(in: pane)

        #expect(didApprove)
        #expect(first.all == [.allow])
        #expect(second.all.isEmpty)
        #expect(approvals.pending(in: pane).map(\.subject.summary) == ["supabase db push contra PROD"])
        #expect(changes.items.last?.isSettled(approved: true, remaining: 1) == true)
    }

    @Test func rejectRepliesWithReason() {
        let log = ReplyLog()
        let approvals = approvals()
        approvals.receive(request("terraform destroy", log: log))
        let subject = approvals.pending(in: pane)[0].subject

        _ = approvals.rejectOldest(in: pane)

        #expect(log.all == [.deny(GuardReasons.rejected(subject))])
    }

    @Test func approveAndRejectByID() {
        let first = ReplyLog()
        let second = ReplyLog()
        let approvals = approvals()
        approvals.receive(request("terraform destroy", log: first))
        approvals.receive(request("terraform apply", pane: PaneID(), log: second))
        let ids = approvals.allPending.map(\.id)

        approvals.reject(ids[1])
        approvals.approve(ids[0])

        #expect(first.all == [.allow])
        #expect(second.all.count == 1)
        #expect(approvals.allPending.isEmpty)
    }

    @Test func expireDeniesAfterDeadline() {
        let log = ReplyLog()
        let approvals = approvals()
        approvals.receive(request("terraform destroy", log: log))

        approvals.expire(now: t0.addingTimeInterval(AgentApprovals.standardTimeout - 1))
        #expect(log.all.isEmpty)
        #expect(approvals.nextDeadline == t0.addingTimeInterval(AgentApprovals.standardTimeout))

        approvals.expire(now: t0.addingTimeInterval(AgentApprovals.standardTimeout))
        #expect(log.all == [.deny(GuardReasons.expired(minutes: 10))])
        #expect(approvals.nextDeadline == nil)
    }

    @Test func shortTimeoutSaysOneMinute() {
        let log = ReplyLog()
        let approvals = AgentApprovals(home: "/Users/u", timeout: 3)
        approvals.receive(request("terraform destroy", log: log))

        approvals.expire(now: t0.addingTimeInterval(3))

        #expect(log.all == [.deny(GuardReasons.expired(minutes: 1))])
    }

    @Test func closingPaneDeniesItsRequests() {
        let mine = ReplyLog()
        let other = ReplyLog()
        let approvals = approvals()
        approvals.receive(request("terraform destroy", log: mine))
        approvals.receive(request("terraform destroy", pane: PaneID(), log: other))

        approvals.paneClosed(pane)

        #expect(mine.all == [.deny(GuardReasons.paneClosed)])
        #expect(other.all.isEmpty)
    }

    @Test func stopDeniesAll() {
        let log = ReplyLog()
        let approvals = approvals()
        approvals.receive(request("terraform destroy", log: log))
        approvals.receive(request("terraform apply", log: log))

        approvals.stop()

        #expect(log.all == [.deny(GuardReasons.unreachable), .deny(GuardReasons.unreachable)])
    }

    @Test func tooManyPendingDeniesThe33rd() {
        let log = ReplyLog()
        let approvals = approvals()
        for _ in 0..<AgentApprovals.maximumPending { approvals.receive(request("terraform destroy", log: ReplyLog())) }

        approvals.receive(request("terraform destroy", log: log))

        #expect(log.all == [.deny(GuardReasons.tooManyPending)])
        #expect(approvals.allPending.count == AgentApprovals.maximumPending)
    }

    /// Review 1 (C1): a command the CLI cut to send it cannot be judged again: it always asks.
    @Test func truncatedRequestAlwaysAsks() {
        let log = ReplyLog()
        let approvals = approvals()
        let use = ToolUse(tool: "Bash", command: "echo hi", cwd: "/p")
        let request = GuardRequest(
            id: UUID(), pane: pane, use: use, environmentHosts: [], localVerdict: .allow, receivedAt: t0,
            isTruncated: true, reply: { log.record($0) })

        approvals.receive(request)

        #expect(log.all.isEmpty)
        #expect(approvals.pending(in: pane).first?.subject.findings.map(\.rule) == [ScreenToolUse.oversizedRule])
    }

    @Test func approveOnEmptyPaneReturnsFalse() {
        let approvals = approvals()

        #expect(!approvals.approveOldest(in: pane))
        #expect(!approvals.rejectOldest(in: pane))
    }

    @Test func replyHappensOnce() {
        let log = ReplyLog()
        let approvals = approvals()
        approvals.receive(request("terraform destroy", log: log))
        let id = approvals.allPending[0].id

        approvals.approve(id)
        approvals.approve(id)
        approvals.reject(id)

        #expect(log.all == [.allow])
    }
}

extension AgentApprovalChange {
    func isSettled(approved: Bool, remaining: Int) -> Bool {
        if case .settled(_, let wasApproved, let left) = self { return wasApproved == approved && left == remaining }
        return false
    }
}
