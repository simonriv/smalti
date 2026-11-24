import SmaltiCore
import Testing

@Suite("ANSIPalette")
struct ANSIPaletteTests {
    private let red = RGBAColor(red: 255, green: 0, blue: 0, alpha: 1)

    @Test func overridesReplaceOnlyTheirIndex() throws {
        let base = Theme.obsidian.terminal.palette

        let palette = try ANSIPalette(base: base, overrides: [1: red])

        #expect(palette.colors[1] == red)
        #expect(
            palette.colors.enumerated().filter { $0.offset != 1 }.map(\.element)
                == base.enumerated().filter { $0.offset != 1 }.map(\.element))
    }

    @Test func noOverridesKeepsBase() throws {
        let base = Theme.obsidian.terminal.palette

        #expect(try ANSIPalette(base: base, overrides: [:]).colors == base)
    }

    @Test(arguments: [16, -1])
    func indexOutsideSixteenIsRejected(_ index: Int) {
        #expect(throws: ColorError.ansiIndexOutOfRange(index)) {
            try ANSIPalette(base: Theme.obsidian.terminal.palette, overrides: [index: red])
        }
    }

    @Test func boundaryIndicesAreAccepted() throws {
        let palette = try ANSIPalette(base: Theme.obsidian.terminal.palette, overrides: [0: red, 15: red])

        #expect(palette.colors.first == red)
        #expect(palette.colors.last == red)
    }
}
