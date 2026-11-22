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

    /// Shrinks every side by `amount`; width and height never go below 0.
    public func insetBy(_ amount: Double) -> Rect {
        Rect(
            x: origin.x + amount,
            y: origin.y + amount,
            width: max(0, size.width - 2 * amount),
            height: max(0, size.height - 2 * amount))
    }
}
