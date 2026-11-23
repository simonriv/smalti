import SmaltiCore
import Testing

@Suite("MenuPlacement")
struct MenuPlacementTests {
    private let tokens = Theme.obsidian.inputMenu
    private let cell = Rect(x: 100, y: 40, width: 8, height: 21)

    @Test func menuBelowWhenSixRowsFit() {
        let frame = MenuPlacement.frame(cursor: cell, pane: Size(width: 800, height: 600), rows: 3, tokens: tokens)

        #expect(frame.origin.y == cell.origin.y + cell.size.height + tokens.cursorGap)
        #expect(frame.origin.x == cell.origin.x)
        #expect(frame.size.width == tokens.width)
    }

    @Test func heightCoversRowsUpToTheVisibleMaximum() {
        let three = MenuPlacement.frame(cursor: cell, pane: Size(width: 800, height: 600), rows: 3, tokens: tokens)
        let twenty = MenuPlacement.frame(cursor: cell, pane: Size(width: 800, height: 900), rows: 20, tokens: tokens)

        #expect(three.size.height == MenuPlacement.height(rows: 3, tokens: tokens))
        #expect(twenty.size.height == MenuPlacement.height(rows: tokens.maximumVisibleRows, tokens: tokens))
    }

    @Test func menuFlipsAboveNearBottom() {
        let low = Rect(x: 100, y: 560, width: 8, height: 21)

        let frame = MenuPlacement.frame(cursor: low, pane: Size(width: 800, height: 600), rows: 3, tokens: tokens)

        #expect(frame.origin.y + frame.size.height == low.origin.y - tokens.cursorGap)
    }

    @Test func menuShiftsLeftNearRightEdge() {
        let right = Rect(x: 700, y: 40, width: 8, height: 21)

        let frame = MenuPlacement.frame(cursor: right, pane: Size(width: 800, height: 600), rows: 3, tokens: tokens)

        #expect(frame.origin.x + frame.size.width == 800)
    }

    @Test func menuFollowsCellAfterResize() {
        let wide = MenuPlacement.frame(cursor: cell, pane: Size(width: 800, height: 600), rows: 3, tokens: tokens)
        let narrow = MenuPlacement.frame(cursor: cell, pane: Size(width: 300, height: 600), rows: 3, tokens: tokens)

        #expect(wide.origin.x == 100)
        #expect(narrow.origin.x == 0)
    }

    @Test func boardValues() {
        #expect(tokens.width == 360)
        #expect(tokens.cornerRadius == 10)
        #expect(tokens.padding == 5)
        #expect(tokens.nameColumnWidth == 92)
        #expect(tokens.rowFontSize == 12)
        #expect(tokens.rowsBelowCursor == 6)
        #expect(tokens.maximumVisibleRows == 8)
    }
}
