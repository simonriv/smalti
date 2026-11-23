/// Where the Tab menu goes in its pane (points, origin top-left, as `cursorCell`): under the cursor's cell when
/// `rowsBelowCursor` rows fit there, above it otherwise, moved left so it never leaves the pane.
public enum MenuPlacement {
    public static func frame(cursor: Rect, pane: Size, rows: Int, tokens: InputMenuTokens) -> Rect {
        let menuHeight = Self.height(rows: rows, tokens: tokens)
        let below = cursor.origin.y + cursor.size.height + tokens.cursorGap
        let fitsBelow =
            below + Self.height(rows: tokens.rowsBelowCursor, tokens: tokens) <= pane.height
        let y = fitsBelow ? below : max(cursor.origin.y - tokens.cursorGap - menuHeight, 0)
        let x = max(min(cursor.origin.x, pane.width - tokens.width), 0)
        return Rect(x: x, y: y, width: tokens.width, height: menuHeight)
    }

    /// Padding, the visible rows (at most `maximumVisibleRows`) with their gaps, and the help line.
    public static func height(rows: Int, tokens: InputMenuTokens) -> Double {
        let visible = Double(min(max(rows, 1), tokens.maximumVisibleRows))
        return tokens.padding * 2 + visible * tokens.rowHeight + (visible - 1) * tokens.rowGap + tokens.footerHeight
    }
}
