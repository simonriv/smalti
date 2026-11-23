import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// Block 2 review m8: the cursor cell comes from `ime_point`'s height in points and the cell's pixel ratio, so it
/// is right on a 1x display and before the view has a window.
@Suite("Cursor cell")
struct CursorCellTests {
    @Test func cellUsesThePointHeightAndThePixelRatio() {
        let cell = CursorCell.rect(
            ime: CursorCell.ImePoint(x: 20, y: 63, height: 21), cellPixels: CursorCell.Pixels(width: 16, height: 42))

        #expect(cell == Rect(x: 16, y: 42, width: 8, height: 21))
    }

    @Test func cellOnAOneXDisplay() {
        let cell = CursorCell.rect(
            ime: CursorCell.ImePoint(x: 4, y: 21, height: 21), cellPixels: CursorCell.Pixels(width: 8, height: 21))

        #expect(cell == Rect(x: 0, y: 0, width: 8, height: 21))
    }

    @Test func emptyCellHasNoRect() {
        #expect(
            CursorCell.rect(
                ime: CursorCell.ImePoint(x: 0, y: 0, height: 0), cellPixels: CursorCell.Pixels(width: 0, height: 0))
                == nil)
    }
}
