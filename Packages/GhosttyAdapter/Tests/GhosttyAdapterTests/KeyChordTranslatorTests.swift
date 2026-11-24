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
        static let equal: UInt16 = 24
        static let slash: UInt16 = 44
        static let quote: UInt16 = 27
        static let latinPlus: UInt16 = 30
    }

    /// `=` is ⇧0 on the Latin American layout: ⌃⇧⌘0 arrives as "=" with ⇧ and must trigger "Igualar paneles" (F4.5:
    /// ⌃⌘=), the same chord as ⌃⌘= on US.
    @Test func shiftedSymbolMatchesTheChordWithoutShift() throws {
        let latin = KeyChordTranslator.chord(
            keyCode: KeyCode.zero, characters: "=", modifiers: [.shift, .control, .command])
        let us = KeyChordTranslator.chord(keyCode: KeyCode.equal, characters: "=", modifiers: [.control, .command])

        #expect(latin == (try KeyChord.parse("ctrl+cmd+=")))
        #expect(latin.flatMap(Keymap.standard.command(for:)) == .panesEqualize)
        #expect(us.flatMap(Keymap.standard.command(for:)) == .panesEqualize)
    }

    /// ⌘+: its own key on Latin American, ⇧= on US. Both increase the font.
    @Test func plusIncreasesTheFontOnBothLayouts() {
        let latin = KeyChordTranslator.chord(keyCode: KeyCode.latinPlus, characters: "+", modifiers: [.command])
        let us = KeyChordTranslator.chord(keyCode: KeyCode.equal, characters: "+", modifiers: [.shift, .command])

        #expect(latin.flatMap(Keymap.standard.command(for:)) == .fontIncrease)
        #expect(us.flatMap(Keymap.standard.command(for:)) == .fontIncrease)
    }

    /// ⌘?: ⇧/ on US, ⇧' on Latin American; both arrive as "?" with ⇧.
    @Test func helpChordIsSameOnUSAndLatinAmerican() {
        let us = KeyChordTranslator.chord(keyCode: KeyCode.slash, characters: "?", modifiers: [.shift, .command])
        let latin = KeyChordTranslator.chord(keyCode: KeyCode.quote, characters: "?", modifiers: [.shift, .command])

        #expect(us.flatMap(Keymap.standard.command(for:)) == .helpShow)
        #expect(latin.flatMap(Keymap.standard.command(for:)) == .helpShow)
    }

    @Test(arguments: [
        (UInt16(116), "pageup"), (121, "pagedown"), (115, "home"), (119, "end"),
    ])
    func translatorNamesPageAndHomeKeys(_ code: UInt16, _ name: String) {
        let chord = KeyChordTranslator.chord(keyCode: code, characters: "\u{F72C}", modifiers: [.command])

        #expect(chord?.key == name)
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

    @Test func keypadEnterIsEnter() {
        #expect(KeyChordTranslator.chord(keyCode: 76, characters: "\u{3}", modifiers: [.command])?.key == "enter")
    }

    @Test func eventWithoutCharactersOrKnownKeyHasNoChord() {
        #expect(KeyChordTranslator.chord(keyCode: 200, characters: nil, modifiers: [.command]) == nil)
    }
}
