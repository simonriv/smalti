import Foundation

/// What a pane's approval card shows (spec F7.5): its oldest waiting command, how many wait, and the keys.
public struct ApprovalCardContent: Equatable, Sendable {
    public let approval: PendingApproval
    public let count: Int
    public let workspace: String
    public let approveKeys: String
    public let rejectKeys: String
    public let now: Date

    public init(approval: PendingApproval, count: Int, workspace: String, keys: Keymap, now: Date) {
        self.approval = approval
        self.count = count
        self.workspace = workspace
        // Review 2: unbound keys point at ⌘K, which lists every waiting command.
        let palette = keys.chord(for: .paletteOpen)?.display ?? "⌘K"
        approveKeys = keys.chord(for: .guardApprove)?.display ?? palette
        rejectKeys = keys.chord(for: .guardReject)?.display ?? palette
        self.now = now
    }

    /// The same waiting command: the card keeps its scroll and selection and only refreshes the counter and footer
    /// (review 2: `now` changes on every refresh).
    public func showsSameCommand(as other: ApprovalCardContent) -> Bool { approval.id == other.approval.id }

    public var counter: String { "1 de \(count)" }

    /// «vence en 10 min», never below 1.
    public var expiresText: String {
        let minutes = max(1, Int((approval.deadline.timeIntervalSince(now) / 60).rounded(.up)))
        return "vence en \(minutes) min"
    }

    public var footer: String { "\(approveKeys) aprobar   \(rejectKeys) rechazar   \(expiresText)" }
}
