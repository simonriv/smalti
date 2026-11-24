import GhosttyKit
import SmaltiCore

/// The terminal cell under the mouse pointer, by column and row of the viewport.
struct PointerCell: Equatable {
    let column: Int
    let row: Int
}

/// Geometry of the word under the pointer, in the view's points with a top-left origin (spec F5.5).
enum PointerWordGeometry {
    /// `baseline` is where libghostty puts the word (`tl_px_x`, `tl_px_y`: its left edge and its text baseline, in
    /// points); the frame covers its cells, the row's full height ending a fifth of a cell below the baseline.
    static func frame(text: String, baseline: Point, cell: Size) -> Rect {
        let width = Double(TerminalText.width(text)) * cell.width
        let top = baseline.y - cell.height * 0.8
        return Rect(x: baseline.x, y: top, width: width, height: cell.height)
    }

}

/// The terminal's cell grid in the view: it starts after the window padding (`window-padding-x/y`, unbalanced, so
/// the top-left padding is exactly the configured one) and has the surface's cell size, both in points.
struct PointerGrid: Equatable {
    let origin: Point
    let cell: Size

    /// The cell under `point`; nil over the padding or when the cell size is not known yet.
    func cell(at point: Point) -> PointerCell? {
        guard cell.width > 0, cell.height > 0, point.x >= origin.x, point.y >= origin.y else { return nil }
        return PointerCell(
            column: Int((point.x - origin.x) / cell.width), row: Int((point.y - origin.y) / cell.height))
    }
}

/// Reads the word libghostty selects at its last mouse position (`ghostty_surface_quicklook_word`). Main thread,
/// like every surface call.
enum PointerWordReader {
    static func word(in surface: ghostty_surface_t, cell: Size) -> PointerWord? {
        var text = ghostty_text_s()
        guard ghostty_surface_quicklook_word(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let bytes = text.text, text.text_len > 0, text.tl_px_x >= 0 else { return nil }
        // Safe: libghostty owns `text_len` bytes at `text` until `ghostty_surface_free_text`, which runs after this
        // copy.
        let buffer = UnsafeRawBufferPointer(start: bytes, count: Int(text.text_len))
        let word = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        let baseline = Point(x: text.tl_px_x, y: text.tl_px_y)
        return PointerWord(text: word, frame: PointerWordGeometry.frame(text: word, baseline: baseline, cell: cell))
    }
}
