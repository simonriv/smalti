import SmaltiCore
import Testing

/// F5: ⌘, opens Apariencia (the macOS Settings convention), ⇧⌘P the prompt studio, ⌥⌘, the config.toml.
@Suite("Keymap · F5")
struct KeymapF5Tests {
    private func chord(_ text: String) throws -> KeyChord { try KeyChord.parse(text) }

    @Test func commaOpensAppearance() throws {
        #expect(Keymap.standard.command(for: try chord("cmd+,")) == .appearanceOpen)
    }

    @Test func shiftCmdPOpensStudio() throws {
        #expect(Keymap.standard.command(for: try chord("shift+cmd+p")) == .promptStudio)
    }

    @Test func optionCmdCommaOpensConfig() throws {
        #expect(Keymap.standard.command(for: try chord("opt+cmd+,")) == .configOpen)
    }

    @Test func plainCmdPStillCyclesObservatoryPeriod() throws {
        #expect(Keymap.standard.command(for: try chord("cmd+p")) == .observatoryPeriod)
    }

    @Test(arguments: [
        CommandID.themeOpen, .themeNext, .ansiReset, .promptApply, .promptExport, .legibilityToggle,
    ])
    func commandsWithoutShortcut(_ command: CommandID) {
        #expect(Keymap.standard.chords(for: command).isEmpty)
    }

    @Test func newShortcutsNeverUseOptionAlone() {
        let chords = [CommandID.appearanceOpen, .promptStudio, .configOpen].flatMap { Keymap.standard.chords(for: $0) }

        #expect(!chords.isEmpty)
        #expect(chords.allSatisfy { !$0.modifiers.contains(.option) || $0.modifiers.contains(.command) })
    }

    @Test func newIdsAreStandard() {
        let ids: [CommandID] = [
            .appearanceOpen, .promptStudio, .themeOpen, .themeNext, .ansiReset, .promptApply, .promptExport,
            .legibilityToggle,
        ]

        #expect(
            ids.map(\.rawValue) == [
                "appearance.open", "prompt.studio", "theme.open", "theme.next", "ansi.reset", "prompt.apply",
                "prompt.export", "legibility.toggle",
            ])
        #expect(ids.allSatisfy(CommandID.allStandard.contains))
    }
}
