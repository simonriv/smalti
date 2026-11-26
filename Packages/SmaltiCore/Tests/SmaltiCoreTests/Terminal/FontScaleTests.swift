import SmaltiCore
import Testing

@Suite("FontScale")
struct FontScaleTests {
    @Test func startsAtTheBase() {
        #expect(FontScale(base: 13).size == 13)
    }

    @Test func stepsOnePointEachWay() {
        let scale = FontScale(base: 13)

        #expect(scale.increased().size == 14)
        #expect(scale.decreased().size == 12)
    }

    @Test func clampsAt6And72() {
        let tiny = (0..<20).reduce(FontScale(base: 13)) { scale, _ in scale.decreased() }
        let huge = (0..<100).reduce(FontScale(base: 13)) { scale, _ in scale.increased() }

        #expect(tiny.size == 6)
        #expect(huge.size == 72)
    }

    @Test func stepsBackRightAfterTheLimit() {
        let atMax = (0..<100).reduce(FontScale(base: 13)) { scale, _ in scale.increased() }

        #expect(atMax.decreased().size == 71)
    }

    @Test func resetReturnsToBase() {
        #expect(FontScale(base: 13).increased().increased().reset().size == 13)
    }

    @Test func rebaseKeepsOffset() {
        #expect(FontScale(base: 13).increased().increased().rebased(16).size == 18)
    }

    @Test func baseOutsideTheLimitsIsClamped() {
        #expect(FontScale(base: 100).size == 72)
        #expect(FontScale(base: 2).size == 6)
    }
}

@Suite("TerminalAppearance · font size")
struct TerminalAppearanceFontSizeTests {
    @Test func scaledKeepsEverythingButTheSize() {
        let base = Theme.obsidian.terminal

        let scaled = base.withFontSize(20)

        #expect(scaled.fontSize == 20)
        #expect(scaled.withFontSize(base.fontSize) == base)
    }

    @Test func scaledKeepsOptionAsMeta() {
        var base = Theme.obsidian.terminal
        base.optionAsMeta = .left

        #expect(base.withFontSize(20).optionAsMeta == .left)
    }
}
