/// A direction of movement between panes.
public enum Direction: CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    public var axis: SplitAxis {
        switch self {
        case .left, .right: .sideBySide
        case .up, .down: .stacked
        }
    }

    /// Whether moving this way goes toward a split's `second` child.
    public var pointsTowardSecond: Bool {
        switch self {
        case .right, .down: true
        case .left, .up: false
        }
    }
}
