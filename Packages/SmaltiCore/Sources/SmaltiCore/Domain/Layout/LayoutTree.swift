/// A binary tree of panes: each split places two subtrees along an axis.
public indirect enum LayoutTree: Hashable, Sendable {
    case leaf(PaneID)
    case split(axis: SplitAxis, ratio: Ratio, first: LayoutTree, second: LayoutTree)

    /// Smallest extent a frame is ever given along either axis.
    private static let minimumFrameExtent = 1.0

    /// Leaves from left to right and from top to bottom.
    public var panes: [PaneID] {
        switch self {
        case .leaf(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.panes + second.panes
        }
    }

    /// Places every pane inside `area`, leaving `gap` between neighbours.
    ///
    /// Gaps are shared out by span (see `span(along:)`), so a ratio of
    /// `span(first) / span(self)` gives every leaf the same size, gaps included.
    public func frames(in area: Rect, gap: Double) -> [PaneID: Rect] {
        var result: [PaneID: Rect] = [:]
        place(in: area, gap: gap, into: &result)
        return result
    }

    /// The same tree with every ratio set so that leaves are equal on each axis.
    public func equalized() -> LayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, _, let first, let second):
            let firstSpan = Double(first.span(along: axis))
            let secondSpan = Double(second.span(along: axis))
            return .split(
                axis: axis,
                ratio: Ratio(firstSpan / (firstSpan + secondSpan)),
                first: first.equalized(),
                second: second.equalized())
        }
    }

    /// How many leaves lie side by side along `axis`: a leaf counts 1, a split
    /// on the same axis adds its children, a split on the other axis takes the
    /// larger child.
    func span(along axis: SplitAxis) -> Int {
        switch self {
        case .leaf:
            return 1
        case .split(let splitAxis, _, let first, let second):
            let firstSpan = first.span(along: axis)
            let secondSpan = second.span(along: axis)
            return splitAxis == axis ? firstSpan + secondSpan : max(firstSpan, secondSpan)
        }
    }

    private func place(in area: Rect, gap: Double, into result: inout [PaneID: Rect]) {
        switch self {
        case .leaf(let id):
            result[id] = area
        case .split(let axis, let ratio, let first, let second):
            let extent = axis == .sideBySide ? area.size.width : area.size.height
            let content = extent - Double(span(along: axis) - 1) * gap
            let firstExtent = max(
                Self.minimumFrameExtent,
                content * ratio.value + Double(first.span(along: axis) - 1) * gap)
            let secondExtent = max(Self.minimumFrameExtent, extent - firstExtent - gap)
            let firstArea: Rect
            let secondArea: Rect
            switch axis {
            case .sideBySide:
                firstArea = Rect(
                    x: area.minX, y: area.minY, width: firstExtent, height: area.size.height)
                secondArea = Rect(
                    x: area.minX + firstExtent + gap, y: area.minY,
                    width: secondExtent, height: area.size.height)
            case .stacked:
                firstArea = Rect(
                    x: area.minX, y: area.minY, width: area.size.width, height: firstExtent)
                secondArea = Rect(
                    x: area.minX, y: area.minY + firstExtent + gap,
                    width: area.size.width, height: secondExtent)
            }
            first.place(in: firstArea, gap: gap, into: &result)
            second.place(in: secondArea, gap: gap, into: &result)
        }
    }
}
