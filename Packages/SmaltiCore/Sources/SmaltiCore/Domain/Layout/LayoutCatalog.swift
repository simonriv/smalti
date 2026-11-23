/// The layout strategies the user can choose from, in display order.
public struct LayoutCatalog: Sendable {
    public static let standard = LayoutCatalog([DwindleLayout(), ColumnsLayout(), MasterStackLayout()])

    public let all: [any LayoutStrategy]

    public init(_ strategies: [any LayoutStrategy]) {
        precondition(!strategies.isEmpty, "a layout catalog needs at least one layout")
        self.all = strategies
    }

    public func strategy(for id: LayoutID) -> (any LayoutStrategy)? {
        all.first { $0.id == id }
    }

    /// The layout named `id`, or the first registered one. Config validation rejects unknown ids, so the fallback
    /// only guards against a catalog that no longer has the configured layout.
    public func strategyOrDefault(for id: LayoutID) -> any LayoutStrategy {
        strategy(for: id) ?? all[0]
    }
}
