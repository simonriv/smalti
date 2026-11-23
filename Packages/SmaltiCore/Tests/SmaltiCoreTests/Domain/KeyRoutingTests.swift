import SmaltiCore
import Testing

@Suite("Key routing")
struct KeyRoutingTests {
    private func chord(_ text: String) throws -> KeyChord { try KeyChord.parse(text) }

    @Test func boundChordPerformsItsCommand() throws {
        let decision = KeyRouting.decide(KeyPress(try chord("cmd+d"), isRepeat: false), keymap: .standard)

        #expect(decision == .perform(.paneNew))
    }

    @Test func unboundChordPassesThrough() throws {
        #expect(KeyRouting.decide(KeyPress(try chord("cmd+y"), isRepeat: false), keymap: .standard) == .passThrough)
    }

    /// Holding ⌘W must not close pane after pane (and kill their processes).
    @Test func repeatOfStructuralCommandIsSwallowed() throws {
        #expect(KeyRouting.decide(KeyPress(try chord("cmd+w"), isRepeat: true), keymap: .standard) == .swallow)
    }

    @Test(arguments: Direction.allCases)
    func repeatOfResizeAndFocusKeepsPerforming(_ direction: Direction) throws {
        let keymap = Keymap.standard
        let resize = try #require(keymap.chord(for: .paneResize(direction)))
        let focus = try #require(keymap.chord(for: .paneFocus(direction)))

        #expect(KeyRouting.decide(KeyPress(resize, isRepeat: true), keymap: keymap) == .perform(.paneResize(direction)))
        #expect(KeyRouting.decide(KeyPress(focus, isRepeat: true), keymap: keymap) == .perform(.paneFocus(direction)))
    }

    @Test func repeatOfUnboundChordPassesThrough() throws {
        #expect(KeyRouting.decide(KeyPress(try chord("cmd+y"), isRepeat: true), keymap: .standard) == .passThrough)
    }

    /// While the palette is open only ⌘K (to close it) runs; other shortcuts must not act behind it.
    @Test func restrictedRoutingSwallowsOtherShortcuts() throws {
        let decision = KeyRouting.decide(
            KeyPress(try chord("cmd+w"), isRepeat: false), keymap: .standard,
            context: KeyContext(allowing: [.paletteOpen]))

        #expect(decision == .swallow)
    }

    @Test func restrictedRoutingStillPerformsAllowedShortcuts() throws {
        let decision = KeyRouting.decide(
            KeyPress(try chord("cmd+k"), isRepeat: false), keymap: .standard,
            context: KeyContext(allowing: [.paletteOpen]))

        #expect(decision == .perform(.paletteOpen))
    }

    @Test func restrictedRoutingLetsTypingThrough() throws {
        let decision = KeyRouting.decide(
            KeyPress(try chord("cmd+y"), isRepeat: false), keymap: .standard,
            context: KeyContext(allowing: [.paletteOpen]))

        #expect(decision == .passThrough)
    }

    /// A plain press is not a repeat unless the system says so.
    @Test func keyPressIsNotARepeatByDefault() throws {
        #expect(!KeyPress(try chord("cmd+w")).isRepeat)
    }

    /// ⌘P cycles the observatory's period only while it is open; closed, the terminal gets the key.
    @Test func inactiveCommandPassesThroughToTheTerminal() throws {
        let decision = KeyRouting.decide(
            KeyPress(try chord("cmd+p")), keymap: .standard, context: KeyContext(passingThrough: [.observatoryPeriod]))

        #expect(decision == .passThrough)
    }

    @Test func activeCommandIsPerformed() throws {
        let decision = KeyRouting.decide(KeyPress(try chord("cmd+p")), keymap: .standard, context: .unrestricted)

        #expect(decision == .perform(.observatoryPeriod))
    }
}
