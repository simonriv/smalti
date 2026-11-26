/// Identity of a layout strategy, stable across sessions.
public struct LayoutID: Hashable, Sendable, RawRepresentable {
    public static let dwindle = LayoutID(rawValue: "dwindle")
    public static let columns = LayoutID(rawValue: "columns")
    public static let master = LayoutID(rawValue: "master")

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A way of arranging panes: builds the tree for an ordered list of panes.
public protocol LayoutStrategy: Sendable {
    var id: LayoutID { get }
    /// Short name shown in the status bar.
    var statusName: String { get }
    /// Icon of its palette command.
    var icon: CommandIcon { get }
    /// The tree holding `panes` in order, or `nil` when there are none.
    func tree(for panes: [PaneID]) -> LayoutTree?
}
