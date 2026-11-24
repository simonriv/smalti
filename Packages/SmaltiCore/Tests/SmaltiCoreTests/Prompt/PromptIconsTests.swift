import SmaltiCore
import Testing

/// Spec F5, "Iconos": thin icons from `SmaltiSymbols` (U+E900 onward, in `PromptIcon` order), Nerd Font glyphs, or none.
@Suite("PromptIcons")
struct PromptIconsTests {
    @Test func thinIconsStartAtE900InOrder() {
        let scalars = PromptIcon.allCases.compactMap {
            PromptIcons.thin.character(for: $0)?.unicodeScalars.first?.value
        }

        #expect(scalars == Array(0xE900..<(0xE900 + UInt32(PromptIcon.allCases.count))))
    }

    @Test func thinIconsStayInTheReservedRange() {
        let last = PromptIcons.thin.character(for: PromptIcon.allCases[PromptIcon.allCases.count - 1])

        #expect((last?.unicodeScalars.first?.value ?? 0) <= 0xE91F)
    }

    @Test func nerdIconsUseNerdFontGlyphs() {
        #expect(PromptIcons.nerd.character(for: .folder) == "\u{F07B}")
        #expect(PromptIcons.nerd.character(for: .branch) == "\u{E0A0}")
        #expect(PromptIcons.nerd.character(for: .node) == "\u{E718}")
        #expect(PromptIcon.allCases.allSatisfy { PromptIcons.nerd.character(for: $0) != nil })
    }

    @Test func noneHasNoIcons() {
        #expect(PromptIcon.allCases.allSatisfy { PromptIcons.none.character(for: $0) == nil })
    }
}
