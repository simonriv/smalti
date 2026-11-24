import SmaltiCore
import Testing

/// Text from file names written to a terminal: control characters never reach it, and width counts cells.
@Suite("TerminalText")
struct TerminalTextTests {
    @Test(arguments: [
        ("a\u{1B}[2J", "a?[2J"), ("a\tb", "a?b"), ("a\u{0}b", "a?b"), ("a\u{7F}", "a?"), ("\u{85}x", "?x"),
        ("foto.png", "foto.png"), ("ñandú.png", "ñandú.png"),
    ])
    func controlCharactersAreReplaced(_ text: String, _ safe: String) {
        #expect(TerminalText.sanitized(text) == safe)
    }

    @Test(arguments: [
        ("abc", 3), ("写真", 4), ("ñ", 1), ("😀", 2), ("", 0), ("🚀", 2), ("🫠", 2), ("❤️", 2), ("🇨🇴", 2),
        ("a\u{200B}b", 2), ("e\u{301}", 1),
    ])
    func widthCountsCells(_ text: String, _ cells: Int) {
        #expect(TerminalText.width(text) == cells)
    }
}
