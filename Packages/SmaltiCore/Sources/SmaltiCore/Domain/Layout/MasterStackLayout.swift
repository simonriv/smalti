/// The first pane on top as master; the others share equal columns below it.
public struct MasterStackLayout: LayoutStrategy {
    /// The master is 1.15 times as tall as the stack (main board).
    private static let masterRatio = Ratio(1.15 / 2.15)

    public let id = LayoutID.master
    public let displayName = "Maestro + pila"
    public let statusName = "maestro"

    private let stack = ColumnsLayout()

    public init() {}

    public func tree(for panes: [PaneID]) -> LayoutTree? {
        guard let master = panes.first else { return nil }
        guard let stackTree = stack.tree(for: Array(panes.dropFirst())) else { return .leaf(master) }
        return .split(axis: .stacked, ratio: Self.masterRatio, first: .leaf(master), second: stackTree)
    }
}
