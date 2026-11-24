/// The thumbnail grid of `smalti img` (spec F5.5): images in natural name order, 12 cells wide (or the terminal's
/// width when narrower), as many per row as fit, each as tall as its proportion asks (1 to 6 rows), with a name and a
/// size below, and a summary at the end.
public struct ImageGrid: Equatable, Sendable {
    public static let cellColumns = 12
    public static let gap = 2
    public static let maxRows = 6
    public static let limit = 100
    /// The name, the size and the prompt under a thumbnail in a short pane.
    static let reservedRows = 3

    public let rows: [GridRow]
    public let columnsPerRow: Int
    public let summary: String

    public static func layout(_ images: [ImageDescription], skipped: Int, in metrics: CellMetrics) -> ImageGrid {
        let sorted = images.sorted { NaturalOrder.precedes($0.name, $1.name) }
        let shown = Array(sorted.prefix(limit))
        let columns = max(1, min(cellColumns, metrics.columns))
        let perRow = max(1, (metrics.columns + gap) / (columns + gap))
        let cells = shown.map { cell(for: $0, columns: columns, in: metrics) }
        let rows = stride(from: 0, to: cells.count, by: perRow).map {
            GridRow(cells: Array(cells[$0..<min($0 + perRow, cells.count)]))
        }
        let summary = Summary.text(shown: shown.count, skipped: skipped, hidden: sorted.count - shown.count)
        return ImageGrid(rows: rows, columnsPerRow: perRow, summary: summary)
    }

    /// A wide image fills the cell's width and reserves its height rounded up; one taller than the cap fills the cap
    /// and is narrower than the cell. Clamped as a `Double` before becoming an `Int`: a zero, infinite or NaN cell
    /// size (a terminal that reports no pixels) or an absurd header gives 1 to 6 rows, never a trap.
    private static func cell(for image: ImageDescription, columns: Int, in metrics: CellMetrics) -> GridCell {
        let rows =
            Double(columns) * metrics.cellWidth * Double(image.pixelHeight)
            / (Double(image.pixelWidth) * metrics.cellHeight)
        let cap = max(1, min(maxRows, metrics.visibleRows - reservedRows))
        guard rows.isFinite, rows > 0 else { return GridCell(image: image, rows: 1, columns: columns, fit: .width) }
        guard rows <= Double(cap) else { return GridCell(image: image, rows: cap, columns: columns, fit: .height) }
        return GridCell(image: image, rows: Int(max(1, rows.rounded(.up))), columns: columns, fit: .width)
    }
}

public struct GridRow: Equatable, Sendable {
    public let cells: [GridCell]

    /// The rows of its tallest thumbnail: where the names go.
    public var height: Int { cells.map(\.rows).max() ?? 0 }
}

public struct GridCell: Equatable, Sendable {
    /// Which side of the cell the thumbnail fills; the terminal keeps its proportion on the other.
    public enum Fit: Equatable, Sendable {
        case width
        case height
    }

    public let image: ImageDescription
    /// Terminal rows the thumbnail takes.
    public let rows: Int
    /// Terminal columns of the cell.
    public let columns: Int
    public let fit: Fit

    /// What the kitty command is told: the filled side only.
    public var box: KittyBox { fit == .width ? .columns(columns) : .rows(rows) }

    /// The name, without control characters, cut to the cell's width in terminal cells, ending in "…" when cut.
    public var label: String {
        let name = TerminalText.sanitized(image.name)
        guard TerminalText.width(name) > columns else { return name }
        var label = ""
        var width = 0
        for character in name {
            width += TerminalText.width(of: character)
            if width > columns - 1 { break }
            label.append(character)
        }
        return label + "…"
    }

    public var dimensions: String { image.dimensions }
}

/// "12 imágenes · 3 omitidas (no son imagen) · … y 23 más (máximo 100)".
enum Summary {
    static func text(shown: Int, skipped: Int, hidden: Int) -> String {
        var parts = [shown == 1 ? "1 imagen" : "\(shown) imágenes"]
        if skipped > 0 {
            parts.append(skipped == 1 ? "1 omitida (no es imagen)" : "\(skipped) omitidas (no son imagen)")
        }
        if hidden > 0 { parts.append("… y \(hidden) más (máximo \(ImageGrid.limit))") }
        return parts.joined(separator: " · ")
    }
}

/// Name order as people read it, the same in every locale: runs of digits compare as numbers, the rest ignoring case.
enum NaturalOrder {
    static func precedes(_ left: String, _ right: String) -> Bool {
        let lhs = chunks(left)
        let rhs = chunks(right)
        for (a, b) in zip(lhs, rhs) where a != b {
            return a < b
        }
        return lhs.count == rhs.count ? left < right : lhs.count < rhs.count
    }

    private static func chunks(_ text: String) -> [Chunk] {
        var chunks: [Chunk] = []
        var current = ""
        for character in text.lowercased() {
            if let last = current.last, isDigit(last) != isDigit(character) {
                chunks.append(Chunk(current))
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { chunks.append(Chunk(current)) }
        return chunks
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private struct Chunk: Comparable {
        let text: String
        let number: String?

        init(_ text: String) {
            self.text = text
            number = text.first.map(NaturalOrder.isDigit) == true ? String(text.drop { $0 == "0" }) : nil
        }

        /// Digits without leading zeros: a longer run is a bigger number, equal lengths compare as text, at any length.
        static func < (lhs: Chunk, rhs: Chunk) -> Bool {
            switch (lhs.number, rhs.number) {
            case (let a?, let b?):
                if a == b { lhs.text < rhs.text } else if a.count != b.count { a.count < b.count } else { a < b }
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): lhs.text < rhs.text
            }
        }
    }
}
