import Foundation

/// What a pane's approval card shows (spec F7.5): its oldest waiting command, how many wait, and the keys.
public struct ApprovalCardContent: Equatable, Sendable {
    public let approval: PendingApproval
    public let count: Int
    public let workspace: String
    public let approveKeys: String
    public let rejectKeys: String
    public let now: Date
    public let texts: GuardTexts

    public init(approval: PendingApproval, count: Int, workspace: String, keys: Keymap, now: Date, texts: GuardTexts) {
        self.approval = approval
        self.count = count
        self.workspace = workspace
        // Review 2: unbound keys point at ⌘K, which lists every waiting command.
        let palette = keys.chord(for: .paletteOpen)?.display ?? "⌘K"
        approveKeys = keys.chord(for: .guardApprove)?.display ?? palette
        rejectKeys = keys.chord(for: .guardReject)?.display ?? palette
        self.now = now
        self.texts = texts
    }

    /// The same waiting command: the card keeps its scroll and selection and only refreshes the counter and footer
    /// (review 2: `now` changes on every refresh).
    public func showsSameCommand(as other: ApprovalCardContent) -> Bool { approval.id == other.approval.id }

    public var counter: String { texts.counter(["count": String(count)]) }

    /// «vence en 10 min», never below 1.
    public var expiresText: String {
        let minutes = max(1, Int((approval.deadline.timeIntervalSince(now) / 60).rounded(.up)))
        return texts.expires(["minutes": String(minutes)])
    }

    public var footer: String {
        texts.footer(["approve": approveKeys, "reject": rejectKeys, "expires": expiresText])
    }
}
