/// A rectangle in points, origin at the top left, y growing downward.
public struct Rect: Hashable, Sendable {
    public let origin: Point
    public let size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = Size(
            width: max(0, size.width),
            height: max(0, size.height))
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(
            origin: Point(x: x, y: y),
            size: Size(width: width, height: height))
    }

    public var minX: Double { origin.x }
    public var maxX: Double { origin.x + size.width }
    public var minY: Double { origin.y }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }

    /// Shrinks every side by `amount`, never more than half the extent on each
    /// axis, so a collapsed rect stays centered inside the original. NaN
    /// counts as no inset.
    public func insetBy(_ amount: Double) -> Rect {
        let safeAmount = amount.isNaN ? 0 : amount
        let insetX = min(safeAmount, size.width / 2)
        let insetY = min(safeAmount, size.height / 2)
        return Rect(
            x: origin.x + insetX,
            y: origin.y + insetY,
            width: size.width - 2 * insetX,
            height: size.height - 2 * insetY)
    }
}
