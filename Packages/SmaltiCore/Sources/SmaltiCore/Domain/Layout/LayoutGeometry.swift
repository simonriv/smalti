/// The area available to panes and the limits a layout must respect inside it.
public struct LayoutGeometry: Hashable, Sendable {
    public static let standardGap = 8.0
    public static let standardMinimumPaneSize = Size(width: 240, height: 120)

    public let area: Rect
    public let gap: Double
    public let minimumPaneSize: Size

    public init(area: Rect, gap: Double, minimumPaneSize: Size) {
        self.area = area
        self.gap = gap
        self.minimumPaneSize = minimumPaneSize
    }

    public static func standard(area: Rect) -> LayoutGeometry {
        LayoutGeometry(
            area: area, gap: standardGap, minimumPaneSize: standardMinimumPaneSize)
    }

    /// Whether every pane of `tree` is at least `minimumPaneSize`.
    public func fits(_ tree: LayoutTree) -> Bool {
        tree.frames(in: area, gap: gap).values.allSatisfy { frame in
            frame.size.width >= minimumPaneSize.width
                && frame.size.height >= minimumPaneSize.height
        }
    }
}
