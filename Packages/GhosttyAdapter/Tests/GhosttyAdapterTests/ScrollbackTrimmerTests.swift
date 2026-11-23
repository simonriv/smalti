import Testing

@testable import GhosttyAdapter

@Suite("Scrollback trimmer")
struct ScrollbackTrimmerTests {
    @Test func trimmerKeepsLastLines() {
        let text = (1...10_001).map { "línea \($0)" }.joined(separator: "\n")

        let trimmed = ScrollbackTrimmer.lastLines(text, count: 10_000)

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 10_000)
        #expect(lines.last == "línea 10001")
        #expect(lines.first?.hasSuffix("línea 2") == true)
    }

    @Test func trimmerPrefixesReset() {
        #expect(ScrollbackTrimmer.lastLines("hola", count: 10).hasPrefix("\u{1B}[0m"))
    }

    @Test func shortTextIsKeptWhole() {
        #expect(ScrollbackTrimmer.lastLines("a\nb", count: 10) == "\u{1B}[0ma\nb")
    }

    @Test func trailingNewlinesAreDropped() {
        #expect(ScrollbackTrimmer.lastLines("a\nb\n\n\n", count: 10) == "\u{1B}[0ma\nb")
    }
}
