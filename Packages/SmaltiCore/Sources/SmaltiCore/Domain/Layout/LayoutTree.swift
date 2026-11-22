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
    ///
    /// Every frame is at least 1 pt on each axis, so panes never collapse. In an
    /// area too small for the tree that floor applies and frames may extend past
    /// `area`: this is intended.
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

    /// Moves the edge of `request.pane` that faces `request.direction`, or
    /// returns `self` when there is no such edge or the result would leave a
    /// pane below `geometry.minimumPaneSize`.
    public func resizing(_ request: ResizeRequest, within geometry: LayoutGeometry) -> LayoutTree {
        guard let resized = movingEdge(of: request), geometry.fits(resized) else { return self }
        return resized
    }

    /// The same tree with the leaves `a` and `b` exchanged, ratios untouched;
    /// `self` when either is not in the tree.
    public func swapping(_ a: PaneID, _ b: PaneID) -> LayoutTree {
        let present = panes
        guard present.contains(a), present.contains(b) else { return self }
        return exchangingLeaves(a, b)
    }

    private func exchangingLeaves(_ a: PaneID, _ b: PaneID) -> LayoutTree {
        switch self {
        case .leaf(let id):
            return .leaf(id == a ? b : (id == b ? a : id))
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis, ratio: ratio,
                first: first.exchangingLeaves(a, b), second: second.exchangingLeaves(a, b))
        }
    }

    /// The pane next to `pane` on the side `direction` points to, or `nil` when
    /// there is none. Among panes beyond that edge that overlap it across the
    /// other axis, the closest wins; ties go to the larger overlap and then to
    /// the earlier pane in `panes`.
    public func neighbor(
        of pane: PaneID, toward direction: Direction, in area: Rect, gap: Double
    ) -> PaneID? {
        let frames = frames(in: area, gap: gap)
        guard let origin = frames[pane] else { return nil }
        let candidates = panes.compactMap { id -> NeighborCandidate? in
            guard id != pane, let frame = frames[id] else { return nil }
            return NeighborCandidate(id: id, frame: frame, origin: origin, direction: direction)
        }
        .filter { $0.isBeyondEdge && $0.overlap > 0 }
        return NeighborCandidate.closestCandidate(candidates)?.id
    }

    /// The tree with the ratio of the nearest ancestor that owns the requested
    /// edge moved, or `nil` when no ancestor owns it.
    private func movingEdge(of request: ResizeRequest) -> LayoutTree? {
        guard case .split(let axis, let ratio, let first, let second) = self else { return nil }
        let inFirst = first.panes.contains(request.pane)
        let child = inFirst ? first : second
        if let resizedChild = child.movingEdge(of: request) {
            return inFirst
                ? .split(axis: axis, ratio: ratio, first: resizedChild, second: second)
                : .split(axis: axis, ratio: ratio, first: first, second: resizedChild)
        }
        let ownsEdge = axis == request.direction.axis && inFirst == request.direction.pointsTowardSecond
        guard ownsEdge else { return nil }
        let delta = request.direction.pointsTowardSecond ? request.step : -request.step
        return .split(axis: axis, ratio: ratio.adding(delta), first: first, second: second)
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

/// A pane considered as the neighbor of `origin` in `direction`.
struct NeighborCandidate {
    /// Slack for frames that touch the edge of the origin up to rounding.
    private static let edgeTolerance = 0.5

    let id: PaneID
    let frame: Rect
    let origin: Rect
    let direction: Direction

    var isBeyondEdge: Bool {
        switch direction {
        case .right: frame.minX >= origin.maxX - Self.edgeTolerance
        case .left: frame.maxX <= origin.minX + Self.edgeTolerance
        case .down: frame.minY >= origin.maxY - Self.edgeTolerance
        case .up: frame.maxY <= origin.minY + Self.edgeTolerance
        }
    }

    /// Distance between the facing edges.
    var distance: Double {
        switch direction {
        case .right: frame.minX - origin.maxX
        case .left: origin.minX - frame.maxX
        case .down: frame.minY - origin.maxY
        case .up: origin.minY - frame.maxY
        }
    }

    /// Length shared with `origin` along the axis perpendicular to `direction`.
    var overlap: Double {
        switch direction.axis {
        case .sideBySide: min(frame.maxY, origin.maxY) - max(frame.minY, origin.minY)
        case .stacked: min(frame.maxX, origin.maxX) - max(frame.minX, origin.minX)
        }
    }

    /// Keeps the candidates within `edgeTolerance` of the smallest facing-edge
    /// distance, then picks the largest overlap; an exact tie keeps the earlier
    /// candidate. Independent of the order of `candidates` except for that tie.
    static func closestCandidate(_ candidates: [NeighborCandidate]) -> NeighborCandidate? {
        guard let nearest = candidates.map(\.distance).min() else { return nil }
        let nearby = candidates.filter { $0.distance - nearest <= edgeTolerance }
        return nearby.reduce(nil as NeighborCandidate?) { best, candidate in
            guard let best else { return candidate }
            return candidate.overlap > best.overlap ? candidate : best
        }
    }
}
