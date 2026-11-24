import SmaltiCore
import Testing

@Suite("KeyChord")
struct KeyChordTests {
    @Test func parsesModifiersAndNamedKeys() throws {
        let chord = try KeyChord.parse("shift+cmd+opt+left")

        #expect(chord.key == "left")
        #expect(chord.modifiers == [.shift, .command, .option])
    }

    @Test func parsesCharacterKeyAndSymbolKey() throws {
        #expect(try KeyChord.parse("ctrl+1") == KeyChord(key: "1", modifiers: [.control]))
        #expect(try KeyChord.parse("cmd+=") == KeyChord(key: "=", modifiers: [.shift, .command]))
    }

    /// Final review: "shift+cmd+1" would silently become ⌘1 and take it from "Ir al panel 1"; it is refused instead.
    @Test(arguments: ["shift+cmd+1", "shift+cmd+=", "shift+ctrl+plus"])
    func refusesShiftOnASymbolKey(_ text: String) {
        #expect(throws: KeyChordError.shiftOnSymbol(text)) { try KeyChord.parse(text) }
    }

    @Test func rejectsUnknownModifier() {
        #expect(throws: KeyChordError.unknownModifier("hyper")) { try KeyChord.parse("hyper+k") }
    }

    @Test func rejectsEmptyAndUnknownKeys() {
        #expect(throws: KeyChordError.missingKey("cmd+")) { try KeyChord.parse("cmd+") }
        #expect(throws: KeyChordError.unknownKey("insert")) { try KeyChord.parse("cmd+insert") }
    }

    @Test func rejectsChordsWithoutCommandControlOrOption() {
        #expect(throws: KeyChordError.missingModifier("d")) { try KeyChord.parse("d") }
        #expect(throws: KeyChordError.missingModifier("shift+d")) { try KeyChord.parse("shift+d") }
    }

    @Test func rejectsRepeatedModifiers() {
        #expect(throws: KeyChordError.duplicateModifier("cmd")) { try KeyChord.parse("cmd+cmd+k") }
        #expect(throws: KeyChordError.duplicateModifier("command")) { try KeyChord.parse("cmd+command+k") }
    }

    @Test func parsesPlusAsANamedKey() throws {
        let chord = try KeyChord.parse("cmd+plus")

        #expect(chord.key == "plus")
        #expect(chord.display == "⌘+")
    }

    @Test func displayUsesAppleOrder() throws {
        #expect(try KeyChord.parse("shift+cmd+opt+left").display == "⌥⇧⌘←")
        #expect(try KeyChord.parse("ctrl+cmd+opt+up").display == "⌃⌥⌘↑")
        #expect(try KeyChord.parse("cmd+opt+c").display == "⌥⌘C")
    }

    @Test func displayRendersEveryNamedKey() throws {
        let rendered = try ["left", "right", "up", "down", "enter", "escape", "tab"].map {
            try KeyChord.parse("cmd+\($0)").display
        }

        #expect(rendered == ["⌘←", "⌘→", "⌘↑", "⌘↓", "⌘↩", "⌘⎋", "⌘⇥"])
    }

    @Test func detectsOptionWithoutCommandOrControl() throws {
        #expect(try KeyChord.parse("opt+c").usesOptionAlone)
        #expect(try KeyChord.parse("shift+opt+c").usesOptionAlone)
        #expect(try !KeyChord.parse("cmd+opt+c").usesOptionAlone)
        #expect(try !KeyChord.parse("ctrl+opt+c").usesOptionAlone)
        #expect(try !KeyChord.parse("cmd+c").usesOptionAlone)
    }
}
