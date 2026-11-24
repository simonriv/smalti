import Foundation

/// What `smalti img` was given: the images (paths with an image extension) and how many other files it skipped.
public struct ImageListing: Equatable, Sendable {
    /// The folder or argument as the user wrote it, for "Sin imágenes en <ruta>".
    public let source: String
    public let images: [String]
    public let skipped: Int

    public init(source: String, images: [String], skipped: Int) {
        self.source = source
        self.images = images
        self.skipped = skipped
    }
}

/// Where `smalti img` writes: the terminal's cell sizes (nil when the output is not a terminal that draws images)
/// and its output.
public protocol GridSink: AnyObject, Sendable {
    var metrics: CellMetrics? { get }
    func write(_ text: String)
}

/// `smalti img` (spec F5.5): the images' grid as kitty graphics, written row by row as each row's thumbnails are ready
/// (final review m3: a large folder never leaves the screen blank), or a plain list of names and sizes when the
/// output is not a terminal. Images that cannot be described or reduced count as skipped.
public enum ShowImageGrid {
    /// Only for the order, the limit and the summary of the plain list.
    private static let listMetrics = CellMetrics(columns: 80, cellWidth: 1, cellHeight: 1)

    public static func render(_ listing: ImageListing, to sink: any GridSink, files: any ImageFiles) async {
        var images: [ImageDescription] = []
        for path in listing.images {
            if let image = try? await files.describe(path) { images.append(image) }
        }
        guard !images.isEmpty else {
            sink.write("Sin imágenes en \(TerminalText.sanitized(listing.source))\n")
            return
        }
        let skipped = listing.skipped + listing.images.count - images.count
        guard let metrics = sink.metrics else {
            sink.write(GridText.list(ImageGrid.layout(images, skipped: skipped, in: listMetrics)))
            return
        }
        let grid = ImageGrid.layout(images, skipped: skipped, in: metrics)
        var drawn = 0
        for row in grid.rows {
            let ready = await thumbnails(of: row, in: metrics, files: files)
            drawn += ready.count
            if !ready.isEmpty { sink.write(GridText.drawing(ready)) }
        }
        let shown = grid.rows.flatMap(\.cells).count
        let hidden = images.count - shown
        sink.write(Summary.text(shown: drawn, skipped: skipped + shown - drawn, hidden: hidden) + "\n")
    }

    /// The row's cells whose thumbnail could be made, each with its PNG; the others are left out (and counted as
    /// skipped).
    private static func thumbnails(of row: GridRow, in metrics: CellMetrics, files: any ImageFiles) async
        -> [(cell: GridCell, png: Data)]
    {
        var ready: [(cell: GridCell, png: Data)] = []
        for cell in row.cells {
            let box = Size(
                width: Double(cell.columns) * metrics.cellWidth, height: Double(cell.rows) * metrics.cellHeight)
            if let png = try? await files.thumbnail(of: cell.image.path, fitting: box) { ready.append((cell, png)) }
        }
        return ready
    }
}

/// The text of the grid: per row, room for its tallest thumbnail, the thumbnails side by side (the cursor stays put
/// after each, `C=1`), then the names and the sizes in secondary text, each padded to its column.
enum GridText {
    private static let escape = "\u{1B}"

    static func drawing(_ row: [(cell: GridCell, png: Data)]) -> String {
        let height = row.map(\.cell.rows).max() ?? 1
        var text = String(repeating: "\n", count: height) + "\(escape)[\(height)A"
        for (cell, png) in row {
            text += KittyPlacement.sequences(png: png, fitting: cell.box).joined()
            text += "\(escape)[\(cell.columns + ImageGrid.gap)C"
        }
        text += "\r\(escape)[\(height)B"
        let cells = row.map(\.cell)
        return text + secondary(cells, \.label) + secondary(cells, \.dimensions)
    }

    static func list(_ grid: ImageGrid) -> String {
        let lines = grid.rows.flatMap(\.cells).map { "\(TerminalText.sanitized($0.image.name))  \($0.dimensions)" }
        return (lines + [grid.summary]).joined(separator: "\n") + "\n"
    }

    private static func secondary(_ cells: [GridCell], _ text: KeyPath<GridCell, String>) -> String {
        let padded = cells.enumerated().map { index, cell in
            let part = cell[keyPath: text]
            guard index < cells.count - 1 else { return part }
            return part + String(repeating: " ", count: cell.columns + ImageGrid.gap - TerminalText.width(part))
        }
        return "\(escape)[2m\(padded.joined())\(escape)[0m\n"
    }
}
