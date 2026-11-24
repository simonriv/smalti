/// Where the preview card goes in its pane (spec F5.5), in the pane's top-left coordinates: under the word, aligned
/// to its start; over it when there is no room below; never out of the pane, at most as wide as the pane, and at its
/// top when the pane is shorter than the card.
public enum PreviewCardPlacement {
    public static func frame(size: Size, word: Rect, pane: Rect, gap: Double) -> Rect {
        let width = min(size.width, pane.size.width)
        let below = word.origin.y + word.size.height + gap
        let above = word.origin.y - gap - size.height
        let preferred = below + size.height <= pane.origin.y + pane.size.height ? below : above
        let y = max(pane.origin.y, min(preferred, pane.origin.y + pane.size.height - size.height))
        let x = max(pane.origin.x, min(word.origin.x, pane.origin.x + pane.size.width - width))
        return Rect(x: x, y: y, width: width, height: size.height)
    }
}
