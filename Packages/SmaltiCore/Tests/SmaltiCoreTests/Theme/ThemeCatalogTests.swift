import SmaltiCore
import Testing

/// Spec F5, "Temas": the four themes, with the colors of `docs/specs/F5-assets/generate-mockups.py` (`THEMES`).
@Suite("ThemeCatalog")
struct ThemeCatalogTests {
    private func hex(_ value: String) -> RGBAColor {
        (try? RGBAColor(hex: value)) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    private func hexes(_ values: String) -> [RGBAColor] {
        values.split(separator: " ").map { hex(String($0)) }
    }

    private struct Expected {
        let id: ThemeID
        let glass, panel, text, title, secondary, ghost, accent: String
        let working, waiting, failed, stopped: String
        let ansi: String
    }

    private var mockupTable: [Expected] {
        [
            Expected(
                id: .niebla, glass: "#eef0f4", panel: "#ffffff", text: "#2a2e36", title: "#1c1f25",
                secondary: "#5c6370", ghost: "#8a909b", accent: "#3b5bdb", working: "#2f9e44", waiting: "#c77c02",
                failed: "#e03131", stopped: "#868e96",
                ansi: "#2a2e36 #c92a2a #237a36 #9a5800 #3b5bdb #9c36b5 #0b7285 #868e96 "
                    + "#495057 #c2255c #1e7b34 #8f5200 #364fc7 #862e9c #0a6e6e #ced4da"),
            Expected(
                id: .ambarNocturno, glass: "#1a1410", panel: "#0c0907", text: "#e8dccb", title: "#f2e8da",
                secondary: "#a39582", ghost: "#6e6355", accent: "#e0af68", working: "#b5c97a", waiting: "#e0af68",
                failed: "#e8826f", stopped: "#7a6e60",
                ansi: "#1f1914 #e8826f #b5c97a #e0af68 #8fa8c8 #c79bc0 #8cc4b8 #d8ccb9 "
                    + "#4a3f33 #f29c8a #c9db92 #f0c88a #a9bfdb #dab3d4 #a6d7cc #f2e8da"),
            Expected(
                id: .bosque, glass: "#0f1714", panel: "#060a08", text: "#cfe0d8", title: "#e2efe9",
                secondary: "#8a9c94", ghost: "#5a6b63", accent: "#6fd3b5", working: "#a6d86b", waiting: "#e3c06f",
                failed: "#ec7f86", stopped: "#62746c",
                ansi: "#141e1a #ec7f86 #a6d86b #e3c06f #74b3e0 #b99be0 #6fd3b5 #b9cbc2 "
                    + "#3c4f47 #f59ca2 #bde68a #eed28e #95c8ee #ceb5ee #92e2ca #e2efe9"),
        ]
    }

    @Test func catalogHasFourThemesInBoardOrder() {
        #expect(ThemeID.allCases == [.obsidiana, .niebla, .ambarNocturno, .bosque])
    }

    @Test func displayNamesMatchBoard() {
        #expect(ThemeID.allCases.map(\.displayName) == ["Obsidiana", "Niebla", "Ámbar nocturno", "Bosque"])
    }

    @Test func configNamesMatchSpec() {
        #expect(ThemeID.allCases.map(\.rawValue) == ["obsidiana", "niebla", "ambar-nocturno", "bosque"])
    }

    @Test func onlyNieblaIsLight() {
        #expect(ThemeID.allCases.filter(\.isLight) == [.niebla])
    }

    @Test func obsidianaIsTheExistingTheme() {
        #expect(ThemeCatalog.theme(.obsidiana) == Theme.obsidian)
    }

    @Test func themeNamesAreDisplayNames() {
        #expect(ThemeID.allCases.map { ThemeCatalog.theme($0).name } == ThemeID.allCases.map(\.displayName))
    }

    @Test func themeColorsMatchMockupTable() {
        for expected in mockupTable {
            let theme = ThemeCatalog.theme(expected.id)
            #expect(theme.window.background == hex(expected.glass).withAlpha(0.62), "\(expected.id)")
            #expect(theme.panel.background == hex(expected.panel).withAlpha(0.34), "\(expected.id)")
            #expect(theme.text.primary == hex(expected.text), "\(expected.id)")
            #expect(theme.text.title == hex(expected.title), "\(expected.id)")
            #expect(theme.text.secondary == hex(expected.secondary), "\(expected.id)")
            #expect(theme.text.ghostText == hex(expected.ghost), "\(expected.id)")
            #expect(theme.accent == hex(expected.accent), "\(expected.id)")
            #expect(theme.agent.working == hex(expected.working), "\(expected.id)")
            #expect(theme.agent.waiting == hex(expected.waiting), "\(expected.id)")
            #expect(theme.agent.failed == hex(expected.failed), "\(expected.id)")
            #expect(theme.agent.stopped == hex(expected.stopped), "\(expected.id)")
            #expect(theme.terminal.palette == hexes(expected.ansi), "\(expected.id)")
        }
    }

    @Test func nieblaHairlinesAreDark() {
        let border = ThemeCatalog.theme(.niebla).window.border

        #expect(border == RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.09))
    }

    @Test func sizesAreSharedByEveryTheme() {
        let obsidian = Theme.obsidian
        for id in ThemeID.allCases {
            let theme = ThemeCatalog.theme(id)
            #expect(theme.panel.cornerRadius == obsidian.panel.cornerRadius)
            #expect(theme.chrome == obsidian.chrome)
            #expect(theme.help == obsidian.help)
            #expect(theme.terminal.fontSize == obsidian.terminal.fontSize)
        }
    }

    /// Spec F5, "Regla de los temas": every protected color passes 4.5:1 on its theme's opaque panel.
    @Test(arguments: ThemeID.allCases)
    func everyThemeProtectedColorPasses4_5OnOwnPanel(_ id: ThemeID) {
        let theme = ThemeCatalog.theme(id)
        let panel = theme.panel.background.withAlpha(1)

        let failing = ThemeCatalog.protectedColors(of: theme, id: id).filter {
            ContrastRatio.between($0, panel) < LegibilityGuard.minimumContrast
        }

        #expect(failing.isEmpty, "\(id): \(failing.map(\.hexString))")
    }

    @Test func protectedColorsSkipTheBackgroundPair() {
        let dark = ThemeCatalog.protectedColors(of: Theme.obsidian, id: .obsidiana)
        let niebla = ThemeCatalog.theme(.niebla)
        let light = ThemeCatalog.protectedColors(of: niebla, id: .niebla)

        #expect(!dark.contains(hex("#414868")))
        #expect(!light.contains(hex("#ced4da")))
        #expect(light.contains(hex("#495057")))
        #expect(dark.count == 16)
    }
}
