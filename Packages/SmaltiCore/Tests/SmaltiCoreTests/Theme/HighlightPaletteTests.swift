import SmaltiCore
import Testing

@Suite("HighlightPalette")
struct HighlightPaletteTests {
    private func theme(_ id: ThemeID, protected: Bool) -> Theme {
        var appearance = AppearanceSettings.obsidian
        appearance.theme = id
        appearance.protectLegibility = protected
        return ThemeCatalog.apply(appearance).theme
    }

    @Test func obsidianPaletteMatchesApprovedRoles() throws {
        let palette = theme(.obsidiana, protected: false).highlightPalette

        #expect(
            [palette.command, palette.unknown, palette.subcommand, palette.option, palette.string, palette.operator]
                .map(\.hexString) == ["#7aa2f7", "#f7768e", "#7dcfff", "#bb9af7", "#9ece6a", "#8b919c"])
    }

    @Test(arguments: ThemeID.allCases)
    func everyRoleReachesContrastWithProtection(_ id: ThemeID) {
        let theme = theme(id, protected: true)
        let ground = id.worstBackdrop.color.underneath(theme.window.background).underneath(theme.panel.background)
        let palette = theme.highlightPalette

        let colors = [
            palette.command, palette.unknown, palette.subcommand, palette.option, palette.string, palette.operator,
        ]

        let low = colors.filter { ContrastRatio.between($0, ground) < LegibilityGuard.minimumContrast }
        #expect(low.isEmpty, "\(id): \(low.map(\.hexString))")
    }

    @Test func highlightStyleEncodesSixColors() {
        let palette = theme(.obsidiana, protected: false).highlightPalette

        #expect(
            InputProtocol.encode(.highlightStyle(palette))
                == "highlightstyle\t#7aa2f7\t#f7768e\t#7dcfff\t#bb9af7\t#9ece6a\t#8b919c")
    }

    @Test func highlightStyleOffEncodes() {
        #expect(InputProtocol.encode(.highlightStyle(nil)) == "highlightstyle\toff")
    }
}
