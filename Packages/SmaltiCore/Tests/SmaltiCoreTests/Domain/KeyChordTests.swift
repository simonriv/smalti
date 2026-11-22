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
        #expect(try KeyChord.parse("shift+cmd+=") == KeyChord(key: "=", modifiers: [.shift, .command]))
    }

    @Test func rejectsUnknownModifier() {
        #expect(throws: KeyChordError.unknownModifier("hyper")) { try KeyChord.parse("hyper+k") }
    }

    @Test func rejectsEmptyAndUnknownKeys() {
        #expect(throws: KeyChordError.missingKey("cmd+")) { try KeyChord.parse("cmd+") }
        #expect(throws: KeyChordError.unknownKey("home")) { try KeyChord.parse("cmd+home") }
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
