/// The share of a split given to its first child, always within `bounds`.
public struct Ratio: Hashable, Sendable {
    public static let bounds: ClosedRange<Double> = 0.1...0.9
    public static let half = Ratio(0.5)

    public let value: Double

    /// Clamps `value` into `bounds`.
    public init(_ value: Double) {
        self.value = min(max(value, Self.bounds.lowerBound), Self.bounds.upperBound)
    }

    public func adding(_ delta: Double) -> Ratio {
        Ratio(value + delta)
    }
}
