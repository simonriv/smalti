import SmaltiCore
import Testing

@Suite("ZshEscaping")
struct ZshEscapingTests {
    @Test func controlCharactersAreDropped() {
        #expect(ZshEscaping.literal("a\u{7}b\u{1b}[31mc") == "ab[31mc")
    }

    @Test func textUpToTheBudgetIsKept() {
        let text = String(repeating: "x", count: ZshEscaping.maximumBytes)

        #expect(ZshEscaping.literal(text) == text)
    }

    @Test func longerTextKeepsItsEnd() {
        let text = String(repeating: "x", count: 200) + "end"

        let literal = ZshEscaping.literal(text)

        #expect(literal.utf8.count <= ZshEscaping.maximumBytes)
        #expect(literal.hasPrefix("…"))
        #expect(literal.hasSuffix("end"))
    }
}

@Suite("ZshEscaping · review")
struct ZshEscapingReviewTests {
    @Test func carriageReturnAndLineSeparatorsBecomeTheNewlineSign() {
        #expect(ZshEscaping.literal("a\rb\u{2028}c") == "a␤b␤c")
    }

    /// psvar shows its values as they are: `%` needs no escaping.
    @Test func percentStaysAsIs() {
        #expect(ZshEscaping.literal("100%F{red}") == "100%F{red}")
    }
}
