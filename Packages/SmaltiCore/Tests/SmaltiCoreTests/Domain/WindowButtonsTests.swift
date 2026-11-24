import SmaltiCore
import Testing

/// Spec F5, "Botones de ventana" and `mockup-buttons`.
@Suite("WindowButtons")
struct WindowButtonsTests {
    @Test func hiddenReservesNoMargin() {
        #expect(!WindowButtons.hidden.reservesStripMargin)
    }

    /// "Al pasar el cursor": the margin is there before the buttons appear, so the pills never move.
    @Test(arguments: [WindowButtons.hover, .visible])
    func shownModesReserveTheMargin(_ mode: WindowButtons) {
        #expect(mode.reservesStripMargin)
    }

    @Test func onlyVisibleShowsThemWithoutTheCursor() {
        #expect(WindowButtons.allCases.filter(\.isAlwaysShown) == [.visible])
    }

    @Test func onlyHoverFollowsTheCursor() {
        #expect(WindowButtons.allCases.filter(\.followsCursor) == [.hover])
    }

    @Test func boardPlacesThemAndShiftsThePills72() {
        let tokens = Theme.obsidian.strip.windowButtons

        #expect(tokens == WindowButtonTokens(pillShift: 72, firstCenterX: 20, spacing: 20))
    }

    @Test func fadeLasts150Milliseconds() {
        #expect(Theme.obsidian.motion.windowButtonsFade == 0.15)
    }
}
