import Testing

@testable import GhosttyAdapter

/// Text attached to a key event: control characters are left for libghostty to encode from the keycode.
/// Regression: a space synthesized with characters "\0" reached zsh as ^@.
@MainActor
@Suite("Key event text")
struct KeyEventTextTests {
    @Test(arguments: ["\0", "\r", "\u{1b}", "\u{7f}x"])
    func dropsTextStartingWithControlCharacter(_ text: String) {
        #expect(GhosttyInput.keyEventText(text) == nil)
    }

    @Test func dropsEmptyAndMissingText() {
        #expect(GhosttyInput.keyEventText("") == nil)
        #expect(GhosttyInput.keyEventText(nil) == nil)
    }

    @Test(arguments: [" ", "a", "á", "@", "ñ"])
    func keepsPrintableText(_ text: String) {
        #expect(GhosttyInput.keyEventText(text) == text)
    }
}
