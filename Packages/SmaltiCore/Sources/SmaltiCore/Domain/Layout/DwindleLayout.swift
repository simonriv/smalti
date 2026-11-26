/// A spiral: the first pane takes the left, each next pane splits the last one,
/// alternating stacked and side by side.
public struct DwindleLayout: LayoutStrategy {
    /// The first pane is 1.35 times as wide as the rest (main board).
    private static let firstSplitRatio = Ratio(1.35 / 2.35)

    public let id = LayoutID.dwindle
    /// Paleta.dc.html icon of this layout's command.
    public let icon = CommandIcon.layoutFrame(strokes: [
        [Point(x: 8.5, y: 2), Point(x: 8.5, y: 14)], [Point(x: 8.5, y: 8), Point(x: 14.5, y: 8)],
    ])

    public init() {}

    public func tree(for panes: [PaneID]) -> LayoutTree? {
        guard let first = panes.first else { return nil }
        guard let rest = subtree(for: panes.dropFirst(), axis: .stacked) else { return .leaf(first) }
        return .split(axis: .sideBySide, ratio: Self.firstSplitRatio, first: .leaf(first), second: rest)
    }

    private func subtree(for panes: ArraySlice<PaneID>, axis: SplitAxis) -> LayoutTree? {
        guard let first = panes.first else { return nil }
        guard let rest = subtree(for: panes.dropFirst(), axis: axis.crossed) else { return .leaf(first) }
        return .split(axis: axis, ratio: .half, first: .leaf(first), second: rest)
    }
}

extension SplitAxis {
    fileprivate var crossed: SplitAxis {
        switch self {
        case .sideBySide: .stacked
        case .stacked: .sideBySide
        }
    }
}
