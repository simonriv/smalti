import SmaltiCore
import Testing

@Suite("ZshEscaping")
struct ZshEscapingTests {
    @Test func controlCharactersAreDropped() {
        #expect(ZshEscaping.literal("a\u{7}b\u{1b}[31mc") == "ab[31mc")
    }

    @Test func textUpTo160CharactersIsKept() {
        let text = String(repeating: "x", count: 160)

        #expect(ZshEscaping.literal(text) == text)
    }

    @Test func longerTextKeepsItsEnd() {
        let text = String(repeating: "x", count: 200) + "end"

        let literal = ZshEscaping.literal(text)

        #expect(literal.count == 160)
        #expect(literal.hasPrefix("…"))
        #expect(literal.hasSuffix("end"))
    }
}
