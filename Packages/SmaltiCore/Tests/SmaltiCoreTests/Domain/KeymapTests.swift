@testable import SmaltiCore
import Testing

@Suite("Keymap")
struct KeymapTests {
    private func chord(_ text: String) throws -> KeyChord { try KeyChord.parse(text) }

    @Test func observatoryToggleIsCommandShiftA() throws {
        #expect(Keymap.standard.command(for: try chord("cmd+shift+a")) == .observatoryToggle)
    }

    @Test func observatoryPeriodIsCommandP() throws {
        #expect(Keymap.standard.command(for: try chord("cmd+p")) == .observatoryPeriod)
    }

    @Test func observatoryCommandsAreStandard() {
        #expect(CommandID.allStandard.contains(.observatoryToggle))
        #expect(CommandID.allStandard.contains(.observatoryPeriod))
        #expect(CommandID.observatoryToggle.rawValue == "observatory.toggle")
        #expect(CommandID.observatoryPeriod.rawValue == "observatory.period")
    }

    @Test func cmdJIsBoundToAgentJump() throws {
        #expect(Keymap.standard.command(for: try chord("cmd+j")) == .agentJump)
    }

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
        #expect(keymap.command(for: try chord("ctrl+cmd+=")) == .panesEqualize)
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

    @Test func movingACommandUnbindsTheOldChordWithNone() throws {
        let newChord = try chord("cmd+j")

        let keymap = try Keymap.standard.overriding([newChord: .paletteOpen, try chord("cmd+k"): nil])

        #expect(keymap.chords(for: .paletteOpen) == [newChord])
    }

    @Test func rebindingUsedChordReleasesPreviousCommand() throws {
        let usedChord = try chord("cmd+d")

        let keymap = try Keymap.standard.overriding([usedChord: .layoutDwindle])

        #expect(keymap.command(for: usedChord) == .layoutDwindle)
        #expect(keymap.chord(for: .paneNew) == nil)
        #expect(keymap.chords(for: .layoutDwindle) == [usedChord])
    }

    @Test func overridingRejectsOptionOnlyChord() throws {
        let reserved = try chord("opt+c")

        #expect(
            throws: ConfigError(file: "", line: nil, key: "⌥C", problem: .reservedOption)
        ) {
            try Keymap.standard.overriding([reserved: .layoutColumns])
        }
    }

    @Test func overridingRejectsOptionOnlyChordDirectly() {
        let reserved = KeyChord(key: "c", modifiers: [.option])

        #expect(
            throws: ConfigError(file: "", line: nil, key: "⌥C", problem: .reservedOption)
        ) {
            try Keymap.standard.overriding([reserved: .layoutColumns])
        }
    }

    @Test func overridingDoesNotChangeTheOriginal() throws {
        let original = Keymap.standard

        _ = try original.overriding([try chord("cmd+j"): .paletteOpen])

        #expect(original == Keymap.standard)
    }

    @Test func bindingOneCommandToTwoChordsAddsBothInDisplayOrder() throws {
        let first = try chord("cmd+j")
        let second = try chord("cmd+m")

        let keymap = try Keymap.standard.overriding([second: .paletteOpen, first: .paletteOpen])

        #expect(keymap.chords(for: .paletteOpen) == [first, second])
    }

    @Test func validateRejectsOptionAloneChord() throws {
        let optionAlone = try chord("opt+k")

        #expect(
            throws: ConfigError(file: "", line: nil, key: "⌥K", problem: .reservedOption)
        ) {
            try Keymap.validate(optionAlone)
        }
    }

    @Test func validateAcceptsOptionWithCommand() throws {
        let chord = try chord("cmd+opt+k")

        #expect(throws: Never.self) { try Keymap.validate(chord) }
    }

    @Test func numberedShortcutsAreOneThroughNine() {
        #expect(NumberedShortcuts.range == 1...9)
    }

    @Test func standardKeymapBindsExactlyTheNumberedShortcutRange() {
        let bindings = Keymap.standard.bindings
        let paneNumbers = Set(NumberedShortcuts.range.filter { bindings.values.contains(.paneFocus($0)) })
        let workspaceNumbers = Set(NumberedShortcuts.range.filter { bindings.values.contains(.workspace($0)) })
        let numbered = Set(NumberedShortcuts.range.flatMap { [CommandID.paneFocus($0), .workspace($0)] })
        let digitKeys = Set(bindings.filter { numbered.contains($0.value) }.keys.compactMap { Int($0.key) })

        #expect(paneNumbers == Set(NumberedShortcuts.range))
        #expect(workspaceNumbers == Set(NumberedShortcuts.range))
        #expect(digitKeys == Set(NumberedShortcuts.range))
    }
}
