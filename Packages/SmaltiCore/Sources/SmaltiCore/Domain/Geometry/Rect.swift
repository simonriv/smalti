/// A rectangle in points, origin at the top left, y growing downward.
public struct Rect: Hashable, Sendable {
    public let origin: Point
    public let size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
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
    /// axis, so a collapsed rect stays centered inside the original.
    public func insetBy(_ amount: Double) -> Rect {
        let insetX = min(amount, size.width / 2)
        let insetY = min(amount, size.height / 2)
        return Rect(
            x: origin.x + insetX,
            y: origin.y + insetY,
            width: size.width - 2 * insetX,
            height: size.height - 2 * insetY)
    }
}
