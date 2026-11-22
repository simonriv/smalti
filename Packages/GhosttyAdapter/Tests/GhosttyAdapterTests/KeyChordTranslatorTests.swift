import AppKit
import SmaltiCore
import Testing

@testable import GhosttyAdapter

/// Review Focus 5: Smalti shortcuts on the Latin American layout.
@Suite("Key chord translation")
struct KeyChordTranslatorTests {
    private enum KeyCode {
        static let zero: UInt16 = 29
        static let q: UInt16 = 12
        static let d: UInt16 = 2
        static let leftArrow: UInt16 = 123
        static let upArrow: UInt16 = 126
        static let escape: UInt16 = 53
    }

    /// `=` is ⇧0 on the Latin American layout, so ⇧⌘0 arrives as "=" with ⇧ and must trigger "Igualar tamaños".
    @Test func shiftedCharacterMatchesShiftedChord() throws {
        let chord = KeyChordTranslator.chord(keyCode: KeyCode.zero, characters: "=", modifiers: [.shift, .command])

        #expect(chord == (try KeyChord.parse("shift+cmd+=")))
        #expect(chord.flatMap(Keymap.standard.command(for:)) == .panesEqualize)
    }

    /// ⌥Q writes `@`; no Smalti shortcut uses ⌥ alone, so it passes to the terminal.
    @Test func optionCharacterPassesThrough() {
        let chord = KeyChordTranslator.chord(keyCode: KeyCode.q, characters: "q", modifiers: [.option])

        #expect(chord.flatMap(Keymap.standard.command(for:)) == nil)
    }

    @Test func arrowsUseKeyCode() throws {
        let left = KeyChordTranslator.chord(
            keyCode: KeyCode.leftArrow, characters: "\u{F702}", modifiers: [.command, .option])
        let up = KeyChordTranslator.chord(keyCode: KeyCode.upArrow, characters: nil, modifiers: [.control])

        #expect(left == (try KeyChord.parse("cmd+opt+left")))
        #expect(up?.key == "up")
    }

    @Test func letterIsLowercasedAndKeepsItsModifiers() throws {
        let chord = KeyChordTranslator.chord(keyCode: KeyCode.d, characters: "D", modifiers: [.command, .option])

        #expect(chord == (try KeyChord.parse("cmd+opt+d")))
    }

    @Test func plusIsNamed() {
        let chord = KeyChordTranslator.chord(keyCode: 24, characters: "+", modifiers: [.command])

        #expect(chord?.key == "plus")
    }

    @Test func escapeUsesKeyCode() {
        #expect(KeyChordTranslator.chord(keyCode: KeyCode.escape, characters: "\u{1B}", modifiers: [])?.key == "escape")
    }

    @Test func eventWithoutCharactersOrKnownKeyHasNoChord() {
        #expect(KeyChordTranslator.chord(keyCode: 200, characters: nil, modifiers: [.command]) == nil)
    }
}
