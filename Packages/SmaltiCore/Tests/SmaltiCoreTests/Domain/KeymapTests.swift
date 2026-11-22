@testable import SmaltiCore
import Testing

@Suite("Keymap")
struct KeymapTests {
    private func chord(_ text: String) throws -> KeyChord { try KeyChord.parse(text) }

    @Test func standardKeymapHasNoOptionOnlyChord() {
        let offenders = Keymap.standard.bindings.keys.filter(\.usesOptionAlone)

        #expect(offenders.isEmpty)
    }

    @Test(arguments: Direction.allCases)
    func standardKeymapBindsDirectionChords(_ direction: Direction) throws {
        let keymap = Keymap.standard
        let arrow = direction.name

        #expect(keymap.command(for: try chord("cmd+opt+\(arrow)")) == .paneFocus(direction))
        #expect(keymap.command(for: try chord("shift+cmd+opt+\(arrow)")) == .paneSwap(direction))
        #expect(keymap.command(for: try chord("ctrl+cmd+opt+\(arrow)")) == .paneResize(direction))
    }

    @Test func standardKeymapBindsTheDocumentedShortcuts() throws {
        let keymap = Keymap.standard

        #expect(keymap.command(for: try chord("cmd+k")) == .paletteOpen)
        #expect(keymap.command(for: try chord("cmd+opt+d")) == .layoutDwindle)
        #expect(keymap.command(for: try chord("cmd+opt+c")) == .layoutColumns)
        #expect(keymap.command(for: try chord("cmd+opt+m")) == .layoutMaster)
        #expect(keymap.command(for: try chord("shift+cmd+=")) == .panesEqualize)
        #expect(keymap.command(for: try chord("cmd+d")) == .paneNew)
        #expect(keymap.command(for: try chord("cmd+w")) == .paneClose)
        #expect(keymap.command(for: try chord("cmd+1")) == .paneFocus(1))
        #expect(keymap.command(for: try chord("cmd+9")) == .paneFocus(9))
        #expect(keymap.command(for: try chord("ctrl+1")) == .workspace(1))
        #expect(keymap.command(for: try chord("ctrl+9")) == .workspace(9))
        #expect(keymap.command(for: try chord("ctrl+cmd+n")) == .workspaceNew)
    }

    @Test func commandsWithoutShortcutStayUnbound() {
        #expect(Keymap.standard.chord(for: .workspaceRename) == nil)
        #expect(Keymap.standard.chord(for: .workspaceClose) == nil)
        #expect(Keymap.standard.chord(for: .configReload) == nil)
    }

    @Test func commandRawValuesAreWhatTomlUsersWrite() {
        #expect(CommandID.paletteOpen.rawValue == "palette.open")
        #expect(CommandID.paneFocus(3).rawValue == "pane.focus.3")
        #expect(CommandID.paneFocus(.up).rawValue == "pane.focus.up")
        #expect(CommandID.paneSwap(.left).rawValue == "pane.swap.left")
        #expect(CommandID.paneResize(.down).rawValue == "pane.resize.down")
        #expect(CommandID.workspace(2).rawValue == "workspace.2")
        #expect(CommandID.panesEqualize.rawValue == "panes.equalize")
    }

    @Test func overridingRebindsAndUnbinds() throws {
        let newChord = try chord("cmd+j")
        let oldChord = try chord("cmd+k")

        let keymap = try Keymap.standard.overriding([newChord: .paletteOpen, try chord("cmd+w"): nil])

        #expect(keymap.command(for: newChord) == .paletteOpen)
        #expect(keymap.chord(for: .paletteOpen) == newChord)
        #expect(keymap.command(for: oldChord) == nil)
        #expect(keymap.chord(for: .paneClose) == nil)
    }

    @Test func rebindingUsedChordReleasesPreviousCommand() throws {
        let usedChord = try chord("cmd+d")

        let keymap = try Keymap.standard.overriding([usedChord: .layoutDwindle])

        #expect(keymap.command(for: usedChord) == .layoutDwindle)
        #expect(keymap.chord(for: .paneNew) == nil)
        #expect(keymap.chord(for: .layoutDwindle) == usedChord)
    }

    @Test func overridingRejectsOptionOnlyChord() throws {
        let reserved = try chord("opt+c")

        #expect(
            throws: ConfigError(file: "", line: nil, key: "⌥C", reason: "⌥ sin ⌘ ni ⌃ queda reservado para escribir")
        ) {
            try Keymap.standard.overriding([reserved: .layoutColumns])
        }
    }

    @Test func overridingDoesNotChangeTheOriginal() throws {
        let original = Keymap.standard

        _ = try original.overriding([try chord("cmd+j"): .paletteOpen])

        #expect(original == Keymap.standard)
    }

    @Test func bindingOneCommandToTwoChordsKeepsTheGreaterDisplay() throws {
        let first = try chord("cmd+j")
        let second = try chord("cmd+m")

        let keymap = try Keymap.standard.overriding([first: .paletteOpen, second: .paletteOpen])

        #expect(keymap.chord(for: .paletteOpen) == KeyChord(key: "m", modifiers: [.command]))
    }

    @Test func validateRejectsOptionAloneChord() throws {
        let optionAlone = try chord("opt+k")

        #expect(
            throws: ConfigError(file: "", line: nil, key: "⌥K", reason: "⌥ sin ⌘ ni ⌃ queda reservado para escribir")
        ) {
            try Keymap.validate(optionAlone)
        }
    }

    @Test func validateAcceptsOptionWithCommand() throws {
        let chord = try chord("cmd+opt+k")

        #expect(throws: Never.self) { try Keymap.validate(chord) }
    }
}
