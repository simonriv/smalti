import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// F5: the engine's config follows the theme (palette, foreground, cursor) and maps Smalti's icon range to its font.
@Suite("Ghostty config text · F5")
struct GhosttyConfigTextF5Tests {
    @Test func configTextCarriesThemePaletteAndCodepointMap() {
        let bosque = ThemeCatalog.theme(.bosque).terminal

        let text = GhosttyConfigText.render(bosque)

        #expect(text.contains("font-codepoint-map = U+E900-U+E91F=SmaltiSymbols"))
        #expect(text.contains("palette = 1=#ec7f86"))
        #expect(text.contains("foreground = #cfe0d8"))
    }

    @Test func iconRangeMatchesThePromptIcons() {
        let last = PromptIcon.allCases.count - 1 + 0xE900

        #expect(last <= 0xE91F)
    }
}
