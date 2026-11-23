/// A `LayoutTree` saved by pane position instead of `PaneID`, because restored panes get new identities.
public indirect enum SnapshotTree: Codable, Equatable, Sendable {
    case leaf(index: Int)
    case split(axis: SplitAxis, ratio: Double, first: SnapshotTree, second: SnapshotTree)

    /// Position of each leaf in `order`. A leaf missing from `order` is saved as an index that never resolves.
    public init(_ tree: LayoutTree, order: [PaneID]) {
        switch tree {
        case .leaf(let id):
            self = .leaf(index: order.firstIndex(of: id) ?? Self.unresolvable)
        case .split(let axis, let ratio, let first, let second):
            self = .split(
                axis: axis, ratio: ratio.value, first: SnapshotTree(first, order: order),
                second: SnapshotTree(second, order: order))
        }
    }

    private static let unresolvable = -1

    /// The tree with `ids[index]` in each leaf, or `nil` when an index has no id (the caller rebuilds the layout).
    public func layoutTree(ids: [PaneID]) -> LayoutTree? {
        switch self {
        case .leaf(let index):
            return ids.indices.contains(index) ? .leaf(ids[index]) : nil
        case .split(let axis, let ratio, let first, let second):
            guard let first = first.layoutTree(ids: ids), let second = second.layoutTree(ids: ids) else { return nil }
            return .split(axis: axis, ratio: Ratio(ratio), first: first, second: second)
        }
    }
}
