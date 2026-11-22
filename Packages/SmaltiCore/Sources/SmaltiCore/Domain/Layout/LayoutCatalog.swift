/// The layout strategies the user can choose from, in display order.
public struct LayoutCatalog: Sendable {
    public static let standard = LayoutCatalog([DwindleLayout(), ColumnsLayout(), MasterStackLayout()])

    public let all: [any LayoutStrategy]

    public init(_ strategies: [any LayoutStrategy]) {
        self.all = strategies
    }

    public func strategy(for id: LayoutID) -> (any LayoutStrategy)? {
        all.first { $0.id == id }
    }
}
