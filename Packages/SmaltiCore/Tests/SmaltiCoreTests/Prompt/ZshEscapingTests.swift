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

    @Test func trimmingNeverLeavesALonePercent() {
        let literal = ZshEscaping.literal(String(repeating: "%", count: 100))

        #expect(literal.dropFirst().count % 2 == 0)
    }
}
