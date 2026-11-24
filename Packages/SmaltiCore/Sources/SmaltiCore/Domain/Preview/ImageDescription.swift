/// An image file as the preview knows it: where it is, its name and its size in pixels.
public struct ImageDescription: Equatable, Sendable {
    public let path: String
    public let name: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(path: String, name: String, pixelWidth: Int, pixelHeight: Int) {
        self.path = path
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// "1440×900", as the card and the grid show it.
    public var dimensions: String { "\(pixelWidth)×\(pixelHeight)" }
}

/// The terminal `smalti img` writes to: its width in cells and the size of one cell in pixels.
public struct CellMetrics: Equatable, Sendable {
    public let columns: Int
    public let cellWidth: Double
    public let cellHeight: Double
    /// Rows the terminal shows (`ws_row`); a thumbnail leaves three of them for its name, its size and the prompt.
    public var visibleRows = Int.max

    public init(columns: Int, cellWidth: Double, cellHeight: Double) {
        self.columns = columns
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
    }
}
