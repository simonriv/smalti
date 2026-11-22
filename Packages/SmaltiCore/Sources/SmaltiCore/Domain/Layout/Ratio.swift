/// The share of a split given to its first child, always within `bounds`.
public struct Ratio: Hashable, Sendable {
    public static let bounds: ClosedRange<Double> = 0.1...0.9
    public static let half = Ratio(0.5)

    public let value: Double

    private static let neutralValue = 0.5

    /// Clamps `value` into `bounds`; NaN becomes an even split.
    public init(_ value: Double) {
        let finiteValue = value.isNaN ? Self.neutralValue : value
        self.value = min(max(finiteValue, Self.bounds.lowerBound), Self.bounds.upperBound)
    }

    public func adding(_ delta: Double) -> Ratio {
        Ratio(value + delta)
    }
}
