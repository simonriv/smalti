@testable import SmaltiCore
import Testing

/// F4.5: the new commands, several chords per command, and the keys with names (⇞ ⇟ ↖ ↘).
@Suite("Keymap · F4.5")
struct KeymapF45Tests {
    private func chord(_ text: String) throws -> KeyChord { try KeyChord.parse(text) }

    /// Mutation (F4.5): two keymaps are equal only when every chord goes to the same command.
    @Test func keymapsDifferingInOneCommandOrOneChordAreNotEqual() throws {
        let base = try Keymap.standard.overriding([try chord("cmd+t"): .paneNew])
        let otherCommand = try Keymap.standard.overriding([try chord("cmd+t"): .workspaceNew])
        let otherChord = try Keymap.standard.overriding([try chord("cmd+y"): .paneNew])

        #expect(base != otherCommand)
        #expect(base != otherChord)
        #expect(base == (try Keymap.standard.overriding([try chord("cmd+t"): .paneNew])))
    }

    @Test(arguments: [
        ("cmd+n", CommandID.windowNew), ("shift+cmd+w", .windowClose), ("ctrl+cmd+f", .windowFullscreen),
        ("cmd+m", .windowMinimize), ("cmd+?", .helpShow), ("cmd+,", .configOpen), ("cmd+c", .terminalCopy),
        ("cmd+v", .terminalPaste), ("cmd+a", .terminalSelectAll), ("cmd+l", .terminalClear), ("cmd+f", .searchOpen),
        ("cmd+g", .searchNext), ("shift+cmd+g", .searchPrevious), ("cmd+plus", .fontIncrease),
        ("cmd+-", .fontDecrease), ("cmd+0", .fontReset), ("cmd+pageup", .scrollPageUp),
        ("cmd+pagedown", .scrollPageDown), ("cmd+home", .scrollTop), ("cmd+end", .scrollBottom),
        ("cmd+up", .promptPrevious), ("cmd+down", .promptNext), ("ctrl+cmd+=", .panesEqualize),
    ])
    func standardBindsEveryNewCommand(_ text: String, _ command: CommandID) throws {
        #expect(Keymap.standard.command(for: try chord(text)) == command)
    }

    @Test(arguments: [
        CommandID.feedbackReport, .logsShow, .appAbout, .secureInputToggle,
    ])
    func commandsOnlyInThePaletteAndMenuHaveNoChord(_ command: CommandID) {
        #expect(Keymap.standard.chords(for: command).isEmpty)
    }

    @Test func newCommandsAreStandardWithTheirIds() {
        let ids = [
            "window.new", "window.close", "window.fullscreen", "window.minimize", "help.show", "feedback.report",
            "logs.show", "app.about", "config.open", "terminal.copy", "terminal.paste", "terminal.selectAll",
            "terminal.clear", "search.open", "search.next", "search.previous", "font.increase", "font.decrease",
            "font.reset", "scroll.pageUp", "scroll.pageDown", "scroll.top", "scroll.bottom", "prompt.previous",
            "prompt.next", "secureInput.toggle",
        ]

        let standard = Set(CommandID.allStandard.map(\.rawValue))

        #expect(ids.allSatisfy(standard.contains))
    }

    @Test func fontIncreaseHasPlusFirstAndEqualsAsAlias() throws {
        let chords = Keymap.standard.chords(for: .fontIncrease)

        #expect(chords == [try chord("cmd+plus"), try chord("cmd+=")])
        #expect(Keymap.standard.chord(for: .fontIncrease) == (try chord("cmd+plus")))
    }

    @Test func equalizeMovedToControlCommandEquals() throws {
        #expect(Keymap.standard.chords(for: .panesEqualize) == [try chord("ctrl+cmd+=")])
    }

    /// On Latin American `=` is ⇧0 and on US `+` is ⇧=: ⇧ belongs to the character, not to the chord.
    @Test(arguments: ["=", "?", "plus", "-", "0", ","])
    func shiftIsPartOfASymbolKey(_ key: String) throws {
        #expect(KeyChord(key: key, modifiers: [.shift, .command]) == (try chord("cmd+\(key)")))
    }

    @Test(arguments: ["a", "left", "pageup"])
    func shiftStaysOnLettersAndNamedKeys(_ key: String) throws {
        #expect(try chord("shift+cmd+\(key)") != (try chord("cmd+\(key)")))
    }

    @Test func bindingAnotherChordReplacesTheDefault() throws {
        let keymap = try Keymap.standard.overriding([try chord("shift+cmd+p"): .paletteOpen])

        #expect(keymap.chords(for: .paletteOpen) == [try chord("shift+cmd+p")])
        #expect(keymap.command(for: try chord("cmd+k")) == nil)
    }

    @Test func orderedBindingsKeepTheirOrderAsAliases() throws {
        let keymap = try Keymap.standard.overriding(ordered: [
            (try chord("cmd+m"), .paletteOpen), (try chord("cmd+j"), .paletteOpen),
        ])

        #expect(keymap.chords(for: .paletteOpen) == [try chord("cmd+m"), try chord("cmd+j")])
    }

    @Test func rebindingMovesEveryAlias() throws {
        let keymap = try Keymap.standard.overriding([try chord("cmd+f"): nil, try chord("ctrl+cmd+f"): .searchOpen])

        #expect(keymap.chords(for: .searchOpen) == [try chord("ctrl+cmd+f")])
        #expect(keymap.chords(for: .windowFullscreen).isEmpty)
    }

    @Test func unbindingAliasKeepsOthers() throws {
        let keymap = try Keymap.standard.overriding([try chord("cmd+="): nil])

        #expect(keymap.chords(for: .fontIncrease) == [try chord("cmd+plus")])
    }

    @Test func unbindingThePrimaryPromotesTheNextAlias() throws {
        let keymap = try Keymap.standard.overriding([try chord("cmd+plus"): nil])

        #expect(keymap.chord(for: .fontIncrease) == (try chord("cmd+=")))
    }

    @Test func oneCommandPerChordStillHolds() throws {
        let keymap = try Keymap.standard.overriding([try chord("cmd+n"): .searchOpen])

        #expect(keymap.command(for: try chord("cmd+n")) == .searchOpen)
        #expect(keymap.chords(for: .windowNew).isEmpty)
    }

    @Test(arguments: [
        ("cmd+pageup", "⌘⇞"), ("cmd+pagedown", "⌘⇟"), ("cmd+home", "⌘↖"), ("cmd+end", "⌘↘"),
    ])
    func namedPageAndHomeKeysParseAndDisplay(_ text: String, _ display: String) throws {
        #expect(try chord(text).display == display)
    }
}
