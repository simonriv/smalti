import Foundation

/// A command waiting for the user in a pane.
public struct PendingApproval: Equatable, Sendable {
    public let id: UUID
    public let pane: PaneID
    public let subject: ApprovalSubject
    public let since: Date
    public let deadline: Date

    public init(id: UUID, pane: PaneID, subject: ApprovalSubject, since: Date, deadline: Date) {
        self.id = id
        self.pane = pane
        self.subject = subject
        self.since = since
        self.deadline = deadline
    }
}

public enum AgentApprovalChange: Equatable, Sendable {
    case waiting(PendingApproval)
    /// Decided, expired or dropped; `remaining` is how many still wait in the same pane.
    case settled(PendingApproval, approved: Bool, remaining: Int)
}

/// The approvals Smalti holds (spec F7.5): it decides each guarded call again with the user's `[guards]`, queues the
/// ones that ask, and answers each exactly once: approved, rejected, expired, pane closed or app stopping.
@MainActor
public final class AgentApprovals {
    public static let standardTimeout: TimeInterval = 600
    public static let maximumPending = 32

    public var settings = GuardSettings.standard
    public var onChange: ((AgentApprovalChange) -> Void)?
    private let home: String
    private let timeout: TimeInterval
    private var queue: [(approval: PendingApproval, reply: @Sendable (GuardDecision) -> Void)] = []

    public init(home: String, timeout: TimeInterval = standardTimeout) {
        self.home = home
        self.timeout = timeout
    }

    public var allPending: [PendingApproval] { queue.map(\.approval) }

    public func pending(in pane: PaneID) -> [PendingApproval] {
        allPending.filter { $0.pane == pane }
    }

    /// The earliest deadline, for the app's timer.
    public var nextDeadline: Date? { allPending.map(\.deadline).min() }

    public func receive(_ request: GuardRequest) {
        if case .deny(let denial) = request.localVerdict { return request.reply(.deny(denial.reason)) }
        let context = GuardContext(settings: settings, environmentHosts: request.environmentHosts)
        switch ScreenToolUse.verdict(for: request.use, context: context, home: home) {
        case .allow: request.reply(.allow)
        case .deny(let denial): request.reply(.deny(denial.reason))
        case .ask(let subject): enqueue(request, subject)
        }
    }

    private func enqueue(_ request: GuardRequest, _ subject: ApprovalSubject) {
        guard queue.count < Self.maximumPending else { return request.reply(.deny(GuardReasons.tooManyPending)) }
        let approval = PendingApproval(
            id: request.id, pane: request.pane, subject: subject, since: request.receivedAt,
            deadline: request.receivedAt.addingTimeInterval(timeout))
        queue.append((approval, request.reply))
        onChange?(.waiting(approval))
    }

    @discardableResult
    public func approveOldest(in pane: PaneID) -> Bool {
        guard let oldest = pending(in: pane).first else { return false }
        approve(oldest.id)
        return true
    }

    @discardableResult
    public func rejectOldest(in pane: PaneID) -> Bool {
        guard let oldest = pending(in: pane).first else { return false }
        reject(oldest.id)
        return true
    }

    public func approve(_ id: UUID) {
        settle(id, with: .allow, approved: true)
    }

    public func reject(_ id: UUID) {
        guard let subject = queue.first(where: { $0.approval.id == id })?.approval.subject else { return }
        settle(id, with: .deny(GuardReasons.rejected(subject)), approved: false)
    }

    public func expire(now: Date) {
        let minutes = max(1, Int((timeout / 60).rounded(.up)))
        for entry in queue where entry.approval.deadline <= now {
            settle(entry.approval.id, with: .deny(GuardReasons.expired(minutes: minutes)), approved: false)
        }
    }

    public func paneClosed(_ pane: PaneID) {
        for approval in pending(in: pane) { settle(approval.id, with: .deny(GuardReasons.paneClosed), approved: false) }
    }

    /// The app is quitting: nobody will answer.
    public func stop() {
        for approval in allPending { settle(approval.id, with: .deny(GuardReasons.unreachable), approved: false) }
    }

    private func settle(_ id: UUID, with decision: GuardDecision, approved: Bool) {
        guard let index = queue.firstIndex(where: { $0.approval.id == id }) else { return }
        let entry = queue.remove(at: index)
        entry.reply(decision)
        let remaining = pending(in: entry.approval.pane).count
        onChange?(.settled(entry.approval, approved: approved, remaining: remaining))
    }
}

/// Shows an approval change on the pane (spec F7.5): amber while it waits, a notification with workspace, command
/// and environment, and working again once nothing waits.
@MainActor
public struct HandleApprovalChange {
    private let notifier: any Notifier

    public init(notifier: any Notifier) {
        self.notifier = notifier
    }

    public func execute(_ change: AgentApprovalChange, in set: inout WorkspaceSet) {
        switch change {
        case .waiting(let approval): wait(approval, in: &set)
        case .settled(let approval, _, let remaining) where remaining == 0:
            update(approval.pane, in: &set) { $0.approvalSettled(in: approval.pane) }
        case .settled: break
        }
    }

    private func wait(_ approval: PendingApproval, in set: inout WorkspaceSet) {
        update(approval.pane, in: &set) {
            $0.waitingForApproval(approval.subject, in: approval.pane, at: approval.since)
        }
        guard let owner = set.workspace(containing: approval.pane),
            let workspace = set.workspaces.first(where: { $0.id == owner }),
            let pane = workspace.panes.first(where: { $0.id == approval.pane })
        else { return }
        let reason = AttentionReason.approval(
            rule: approval.subject.headline?.rule ?? "", environment: approval.subject.environment.label)
        notifier.notify(.make(reason, workspace: workspace.name, directory: pane.workingDirectory, pane: pane.id))
    }

    private func update(_ pane: PaneID, in set: inout WorkspaceSet, _ transform: (Workspace) -> Workspace) {
        guard let owner = set.workspace(containing: pane) else { return }
        set = set.updating(owner, transform)
    }
}
