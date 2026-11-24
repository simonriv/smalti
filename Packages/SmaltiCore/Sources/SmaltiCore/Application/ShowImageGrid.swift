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

/// What the CLI writes and exits with.
public struct GridOutput: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// `smalti img` (spec F5.5): the images' grid as kitty graphics in a terminal, or a plain list of names and sizes when
/// the output is not one (`metrics` nil). Images that cannot be described or reduced count as skipped.
public enum ShowImageGrid {
    /// Only for the order, the limit and the summary of the plain list.
    private static let listMetrics = CellMetrics(columns: 80, cellWidth: 1, cellHeight: 1)

    public static func render(_ listing: ImageListing, metrics: CellMetrics?, files: any ImageFiles) async
        -> GridOutput
    {
        let (images, unreadable) = await describe(listing.images, files: files)
        guard !images.isEmpty else {
            return GridOutput(stdout: "Sin imágenes en \(TerminalText.sanitized(listing.source))\n")
        }
        let skipped = listing.skipped + unreadable
        guard let metrics else {
            return GridOutput(stdout: GridText.list(ImageGrid.layout(images, skipped: skipped, in: listMetrics)))
        }
        let (grid, thumbnails) = await thumbnailed(images, skipped: skipped, in: metrics, files: files)
        return GridOutput(stdout: GridText.drawing(grid, thumbnails: thumbnails))
    }

    private static func describe(_ paths: [String], files: any ImageFiles) async -> ([ImageDescription], Int) {
        var images: [ImageDescription] = []
        for path in paths {
            if let image = try? await files.describe(path) { images.append(image) }
        }
        return (images, paths.count - images.count)
    }

    /// The grid and a thumbnail for each of its cells: an image whose thumbnail fails leaves the grid (it counts as
    /// skipped) and the next one past the limit, if any, takes its place.
    private static func thumbnailed(
        _ images: [ImageDescription], skipped: Int, in metrics: CellMetrics, files: any ImageFiles
    ) async -> (ImageGrid, [String: Data]) {
        var kept = images
        var thumbnails: [String: Data] = [:]
        while true {
            let grid = ImageGrid.layout(kept, skipped: skipped + images.count - kept.count, in: metrics)
            var failed: Set<String> = []
            for cell in grid.rows.flatMap(\.cells) where thumbnails[cell.image.path] == nil {
                let box = Size(
                    width: Double(ImageGrid.cellColumns) * metrics.cellWidth,
                    height: Double(cell.rows) * metrics.cellHeight)
                do {
                    thumbnails[cell.image.path] = try await files.thumbnail(of: cell.image.path, fitting: box)
                } catch {
                    failed.insert(cell.image.path)
                }
            }
            guard !failed.isEmpty else { return (grid, thumbnails) }
            kept.removeAll { failed.contains($0.path) }
        }
    }
}

/// The text of the grid: per row, room for its tallest thumbnail, the thumbnails side by side (the cursor stays put
/// after each, `C=1`), then the names and the sizes in secondary text, each padded to its column.
enum GridText {
    private static let column = ImageGrid.cellColumns + ImageGrid.gap
    private static let escape = "\u{1B}"

    static func drawing(_ grid: ImageGrid, thumbnails: [String: Data]) -> String {
        var text = ""
        for row in grid.rows {
            text += String(repeating: "\n", count: row.height) + "\(escape)[\(row.height)A"
            for cell in row.cells {
                let png = thumbnails[cell.image.path] ?? Data()
                text += KittyPlacement.sequences(png: png, columns: ImageGrid.cellColumns, rows: cell.rows).joined()
                text += "\(escape)[\(column)C"
            }
            text += "\r\(escape)[\(row.height)B"
            text += secondary(row.cells.map(\.label)) + secondary(row.cells.map(\.dimensions))
        }
        return text + grid.summary + "\n"
    }

    static func list(_ grid: ImageGrid) -> String {
        let lines = grid.rows.flatMap(\.cells).map { "\(TerminalText.sanitized($0.image.name))  \($0.dimensions)" }
        return (lines + [grid.summary]).joined(separator: "\n") + "\n"
    }

    private static func secondary(_ parts: [String]) -> String {
        let padded = parts.enumerated().map { index, part in
            index == parts.count - 1 ? part : part + String(repeating: " ", count: column - TerminalText.width(part))
        }
        return "\(escape)[2m\(padded.joined())\(escape)[0m\n"
    }
}
