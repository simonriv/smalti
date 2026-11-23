/// Where the Tab menu goes in its pane (points, origin top-left, as `cursorCell`): under the cursor's cell when
/// `rowsBelowCursor` rows fit there, above it otherwise; always inside the pane (moved up or left, and never wider
/// than it).
public enum MenuPlacement {
    public static func frame(cursor: Rect, pane: Size, rows: Int, tokens: InputMenuTokens) -> Rect {
        let menuHeight = Self.height(rows: rows, tokens: tokens)
        let below = cursor.origin.y + cursor.size.height + tokens.cursorGap
        let fitsBelow =
            below + Self.height(rows: tokens.rowsBelowCursor, tokens: tokens) <= pane.height
        let wanted = fitsBelow ? below : cursor.origin.y - tokens.cursorGap - menuHeight
        let y = max(min(wanted, pane.height - menuHeight), 0)
        let width = min(tokens.width, pane.width)
        let x = max(min(cursor.origin.x, pane.width - width), 0)
        return Rect(x: x, y: y, width: width, height: menuHeight)
    }

    /// Padding, the visible rows (at most `maximumVisibleRows`) with their gaps, and the help line.
    public static func height(rows: Int, tokens: InputMenuTokens) -> Double {
        let visible = Double(min(max(rows, 1), tokens.maximumVisibleRows))
        return tokens.padding * 2 + visible * tokens.rowHeight + (visible - 1) * tokens.rowGap + tokens.footerHeight
    }
}
