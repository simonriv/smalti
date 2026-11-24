import SmaltiCore
import Testing

/// Spec F5, "Proteger legibilidad": values computed against the worst desktop, as in `F5-assets/generate-mockups.py`.
@Suite("LegibilityGuard")
struct LegibilityGuardTests {
    private func hex(_ value: String) -> RGBAColor {
        (try? RGBAColor(hex: value)) ?? RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    private func hexes(_ values: String) -> [RGBAColor] {
        values.split(separator: " ").map { hex(String($0)) }
    }

    /// Text, secondary and the ANSI colors but 0 and 8 (Obsidiana).
    private var obsidianProtected: [RGBAColor] {
        hexes(
            "#d7dae0 #8b919c #f7768e #9ece6a #e0af68 #7aa2f7 #bb9af7 #7dcfff #a9b1d6 "
                + "#ff99ad #b9f27c #ffc777 #a3bdfa #d3b8ff #a4e3ff #c0caf5")
    }

    private var obsidianGlassOverWhite: RGBAColor {
        Backdrop.white.color.underneath(hex("#0d0f15").withAlpha(0.62))
    }

    /// Spec F5 gave 65 % for exactly 4.5; the search keeps a 0.05 margin over it (block 1 review, I1).
    @Test func obsidianPanelNeeds66Percent() {
        let surface = ProtectedSurface(tint: hex("#06070a"), colors: obsidianProtected)

        #expect(LegibilityGuard.minimumOpacity(for: surface, over: obsidianGlassOverWhite) == 0.66)
    }

    @Test func nieblaPanelNeeds83Percent() {
        let protected = hexes(
            "#2a2e36 #5c6370 #2a2e36 #c92a2a #237a36 #9a5800 #3b5bdb #9c36b5 #0b7285 "
                + "#495057 #c2255c #1e7b34 #8f5200 #364fc7 #862e9c #0a6e6e")
        let ground = Backdrop.black.color.underneath(hex("#eef0f4").withAlpha(0.62))

        let opacity = LegibilityGuard.minimumOpacity(
            for: ProtectedSurface(tint: hex("#ffffff"), colors: protected), over: ground)

        #expect(opacity == 0.83)
    }

    @Test func chromeNeeds89Percent() {
        let surface = ProtectedSurface(tint: hex("#0d0f15"), colors: [hex("#d7dae0"), hex("#8b919c")])

        #expect(LegibilityGuard.minimumOpacity(for: surface, over: Backdrop.white.color) == 0.89)
    }

    @Test func colorThatNeverPassesNeedsFullOpacity() {
        let surface = ProtectedSurface(tint: hex("#06070a"), colors: [hex("#15161e")])

        #expect(LegibilityGuard.minimumOpacity(for: surface, over: obsidianGlassOverWhite) == 1)
    }

    @Test func legibleColorsNeedNoOpacity() {
        let surface = ProtectedSurface(tint: hex("#06070a"), colors: [hex("#d7dae0")])

        #expect(LegibilityGuard.minimumOpacity(for: surface, over: Backdrop.black.color) == 0)
    }

    @Test func ghostReaches4_5AfterMixing() {
        let ground = obsidianGlassOverWhite.underneath(hex("#06070a").withAlpha(0.66))

        let ghost = LegibilityGuard.legible(hex("#5f6672"), on: ground, toward: hex("#d7dae0"))

        #expect(ContrastRatio.between(ghost, ground) >= LegibilityGuard.minimumContrast)
        #expect(ghost != hex("#5f6672"))
    }

    @Test func ghostMixingStopsAtFirstPassingStep() {
        let ground = obsidianGlassOverWhite.underneath(hex("#06070a").withAlpha(0.66))
        let ghost = hex("#5f6672")
        let text = hex("#d7dae0")
        let legible = LegibilityGuard.legible(ghost, on: ground, toward: text)
        let step = (1...100).first { ghost.mixed(toward: text, amount: Double($0) / 100) == legible } ?? 0

        let previous = ghost.mixed(toward: text, amount: Double(step - 1) / 100)

        #expect(step > 0)
        // 4.55: the search target, 4.5 plus the margin for unrounded blending.
        #expect(ContrastRatio.between(previous, ground) < 4.55)
    }

    @Test func unreachableUserColorIsAdjusted() {
        let panel = hex("#06070a")

        let adjusted = LegibilityGuard.legible(hex("#15161e"), on: panel, toward: hex("#d7dae0"))

        #expect(ContrastRatio.between(adjusted, panel) >= LegibilityGuard.minimumContrast)
    }

    @Test func alreadyLegibleColorIsUnchanged() {
        let text = hex("#d7dae0")

        #expect(LegibilityGuard.legible(text, on: hex("#06070a"), toward: hex("#ffffff")) == text)
    }

    @Test func adjustedColorsAreCounted() {
        let colors = [hex("#d7dae0"), hex("#15161e"), hex("#414868")]

        let result = LegibilityGuard.legible(colors, on: hex("#06070a"), toward: hex("#d7dae0"))

        #expect(result.adjustedCount == 2)
        #expect(result.colors.first == hex("#d7dae0"))
        #expect(result.colors.allSatisfy { ContrastRatio.between($0, hex("#06070a")) >= 4.5 })
    }

    @Test func minimumContrastIs4_5() {
        #expect(LegibilityGuard.minimumContrast == 4.5)
    }
}
