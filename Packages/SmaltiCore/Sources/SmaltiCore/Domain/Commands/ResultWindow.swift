/// Which palette results are built and shown: at most `capacity` consecutive rows around the selection. ↑↓ wrap at
/// the ends and the window follows the selection one row at a time, so opening the palette never lays out rows
/// that cannot be seen (B7: open in 50 ms or less).
public struct ResultWindow: Equatable, Sendable {
    public let count: Int
    public let capacity: Int
    public private(set) var selection = 0
    private var start = 0

    public init(count: Int, capacity: Int) {
        self.count = max(0, count)
        self.capacity = max(1, capacity)
    }

    /// Indices of the rows on screen.
    public var visible: Range<Int> { start..<min(count, start + capacity) }

    public func moving(by step: Int) -> ResultWindow {
        guard count > 0 else { return self }
        var moved = self
        moved.selection = ((selection + step) % count + count) % count
        moved.start = moved.startKeeping(moved.selection)
        return moved
    }

    private func startKeeping(_ index: Int) -> Int {
        if index < start { return index }
        if index >= start + capacity { return index - capacity + 1 }
        return start
    }
}
