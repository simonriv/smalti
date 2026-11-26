/// What the timeline follows in the focused pane (review 2 of F9): which session, the project's root and the pane.
/// The pane's look (its state dot, its name changing language) only repaints; another session reads it.
public struct TimelineFocus: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case read
        case repaint
    }

    public let resolution: TimelineTarget.Resolution
    public let root: String
    /// The pane, by its place ("acme · 1"): a pinned session stays until the focus moves to another pane.
    public let pane: String

    public init(resolution: TimelineTarget.Resolution, root: String, pane: String) {
        self.resolution = resolution
        self.root = root
        self.pane = pane
    }

    public static func change(from previous: TimelineFocus?, to next: TimelineFocus, isPinned: Bool) -> Change {
        guard let previous else { return .read }
        if isPinned { return previous.pane == next.pane ? .repaint : .read }
        return previous == next ? .repaint : .read
    }
}
