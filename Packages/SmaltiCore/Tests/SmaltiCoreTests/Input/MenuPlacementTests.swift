@testable import SmaltiCore
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

    // Block 4 review I3: eight rows near the bottom never leave the pane; neither does a narrow pane.
    @Test func menuWithEightRowsNeverLeavesThePane() {
        let cursor = Rect(x: 100, y: 340, width: 8, height: 21)

        let frame = MenuPlacement.frame(cursor: cursor, pane: Size(width: 800, height: 600), rows: 8, tokens: tokens)

        #expect(frame.origin.y + frame.size.height <= 600)
        #expect(frame.origin.y >= 0)
    }

    @Test func menuIsNeverWiderThanThePane() {
        let frame = MenuPlacement.frame(cursor: cell, pane: Size(width: 300, height: 600), rows: 3, tokens: tokens)

        #expect(frame.size.width == 300)
        #expect(frame.origin.x == 0)
    }

    // Block 4 review m4: the ⌃R palette's measures live in the theme (approved mockup over Paleta.dc.html).
    @Test func historyPaletteValues() {
        let palette = Theme.obsidian.historyPalette

        #expect(palette.widthFraction == 0.86)
        #expect(palette.minimumWidth == 480)
        #expect(palette.maximumWidth == 720)
        #expect(palette.rowHeight == 32)
        #expect(palette.visibleRows == 8)
        #expect(Theme.obsidian.motion.overlayAppearDuration == 0.12)
    }

    // Mutation survivor (F4 close): every term of the height, with values that tell them apart.
    @Test func heightAddsPaddingRowsGapsAndHelpLine() {
        let menu = Theme.obsidian.inputMenu
        let tokens = InputMenuTokens(
            width: menu.width, cornerRadius: menu.cornerRadius, border: menu.border, background: menu.background,
            shadowRadius: menu.shadowRadius, shadowOffsetY: menu.shadowOffsetY, shadowOpacity: menu.shadowOpacity,
            padding: 5, rowFontSize: menu.rowFontSize, rowHeight: 20, rowGap: 3,
            rowCornerRadius: menu.rowCornerRadius, rowPaddingHorizontal: menu.rowPaddingHorizontal,
            nameColumnWidth: menu.nameColumnWidth, columnGap: menu.columnGap, footerHeight: 24,
            footerFontSize: menu.footerFontSize, footerTopGap: menu.footerTopGap, textLineHeight: menu.textLineHeight,
            cursorGap: menu.cursorGap, rowsBelowCursor: menu.rowsBelowCursor, maximumVisibleRows: 8)

        // 5 × 2 padding + 3 × 20 rows + 2 × 3 gaps + 24 help line.
        #expect(MenuPlacement.height(rows: 3, tokens: tokens) == 100)
    }
}
