/// A request to move the edge of `pane` that faces `direction` by `step`.
public struct ResizeRequest: Hashable, Sendable {
    /// Share of a split moved per key press.
    public static let defaultStep = 0.05

    public let pane: PaneID
    public let direction: Direction
    public let step: Double

    public init(pane: PaneID, direction: Direction, step: Double) {
        self.pane = pane
        self.direction = direction
        self.step = step
    }
}
