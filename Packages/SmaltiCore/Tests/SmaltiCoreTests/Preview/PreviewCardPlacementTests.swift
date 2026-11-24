import SmaltiCore
import Testing

/// Spec F5.5: the card goes under the word, aligned to its start; over it when there is no room below; never out of
/// the pane (block 4 review I3: not even when its caption makes it wider than the pane). Pane coordinates, top-left.
@Suite("Preview card placement")
struct PreviewCardPlacementTests {
    private let pane = Rect(x: 0, y: 0, width: 600, height: 400)
    private let card = Size(width: 210, height: 140)

    private func frame(word: Rect, size: Size? = nil) -> Rect {
        PreviewCardPlacement.frame(size: size ?? card, word: word, pane: pane, gap: 4)
    }

    @Test func goesUnderTheWordAtItsStart() {
        #expect(frame(word: Rect(x: 40, y: 20, width: 64, height: 20)) == Rect(x: 40, y: 44, width: 210, height: 140))
    }

    @Test func flipsAboveAtTheBottom() {
        #expect(frame(word: Rect(x: 40, y: 360, width: 64, height: 20)) == Rect(x: 40, y: 216, width: 210, height: 140))
    }

    @Test func staysInsideOnTheRight() {
        #expect(frame(word: Rect(x: 560, y: 20, width: 40, height: 20)).origin.x == 390)
    }

    @Test func staysInsideOnTheLeft() {
        #expect(frame(word: Rect(x: -10, y: 20, width: 40, height: 20)).origin.x == 0)
    }

    @Test func neverWiderThanThePane() {
        let wide = frame(word: Rect(x: 40, y: 20, width: 64, height: 20), size: Size(width: 700, height: 140))

        #expect(wide.origin.x == 0 && wide.size.width == 600)
    }

    @Test func tallCardInAShortPaneStartsAtItsTop() {
        let short = PreviewCardPlacement.frame(
            size: card, word: Rect(x: 40, y: 60, width: 64, height: 20),
            pane: Rect(x: 0, y: 0, width: 600, height: 150),
            gap: 4)

        #expect(short.origin.y == 0)
        #expect(short.size.height == 140)
    }

    /// A word in the bottom padding, past the pane's last row: the card still ends inside the pane.
    @Test func wordPastTheBottomKeepsCardInside() {
        #expect(frame(word: Rect(x: 40, y: 500, width: 64, height: 20)).origin.y == 260)
    }
}
