import SmaltiCore
import Testing

@Suite("ContrastRatio")
struct ContrastRatioTests {
    private let white = RGBAColor(red: 255, green: 255, blue: 255, alpha: 1)
    private let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)

    @Test func whiteOnBlackIs21() {
        #expect(ContrastRatio.between(white, black) == 21)
    }

    @Test func sameColorIs1() throws {
        let accent = try RGBAColor(hex: "#7aa2f7")

        #expect(ContrastRatio.between(accent, accent) == 1)
    }

    @Test func orderDoesNotMatter() throws {
        let text = try RGBAColor(hex: "#d7dae0")

        #expect(ContrastRatio.between(text, black) == ContrastRatio.between(black, text))
    }

    /// Spec F5: `#d7dae0` over the panel at 34 % over the glass at 62 % over a white desktop. The spec's 6.48 was
    /// computed in floating point; composited in 8-bit channels, as on screen, the ground is (71, 72, 76) and 6.52.
    @Test func obsidianTextOnWorstPanelIs6_52() throws {
        let ground = Backdrop.white.color
            .underneath(try RGBAColor(hex: "#0d0f15").withAlpha(0.62))
            .underneath(try RGBAColor(hex: "#06070a").withAlpha(0.34))

        let ratio = ContrastRatio.between(try RGBAColor(hex: "#d7dae0"), ground)

        #expect(abs(ratio - 6.52) < 0.01)
    }

    @Test func compositingHalfBlackOverWhiteIsMidGrey() {
        let grey = white.underneath(black.withAlpha(0.5))

        #expect(grey == RGBAColor(red: 128, green: 128, blue: 128, alpha: 1))
    }

    @Test func mixingHalfwayLandsBetween() {
        let mixed = black.mixed(toward: white, amount: 0.5)

        #expect(mixed == RGBAColor(red: 128, green: 128, blue: 128, alpha: 1))
    }

    @Test func backdropsAreWhiteAndBlack() {
        #expect(Backdrop.white.color == white)
        #expect(Backdrop.black.color == black)
    }
}
