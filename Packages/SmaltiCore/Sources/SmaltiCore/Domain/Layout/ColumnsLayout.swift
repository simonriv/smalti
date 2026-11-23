/// Every pane in its own full-height column, all of equal width.
public struct ColumnsLayout: LayoutStrategy {
    public let id = LayoutID.columns
    public let displayName = "Columnas"
    public let statusName = "columnas"
    public let subtitle: String? = nil
    /// Paleta.dc.html icon of this layout's command.
    public let icon = CommandIcon.layoutFrame(strokes: [
        [Point(x: 5.8, y: 2), Point(x: 5.8, y: 14)], [Point(x: 10.2, y: 2), Point(x: 10.2, y: 14)],
    ])

    public init() {}

    public func tree(for panes: [PaneID]) -> LayoutTree? {
        guard let first = panes.first else { return nil }
        let rest = Array(panes.dropFirst())
        guard let remaining = tree(for: rest) else { return .leaf(first) }
        // 1/n at each level gives equal columns because gaps are shared by span.
        return .split(
            axis: .sideBySide, ratio: Ratio(1 / Double(panes.count)),
            first: .leaf(first), second: remaining)
    }
}
