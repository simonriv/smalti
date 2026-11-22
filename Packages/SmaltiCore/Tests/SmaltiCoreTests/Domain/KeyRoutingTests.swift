import SmaltiCore
import Testing

@Suite("Key routing")
struct KeyRoutingTests {
    private func chord(_ text: String) throws -> KeyChord { try KeyChord.parse(text) }

    @Test func boundChordPerformsItsCommand() throws {
        let decision = KeyRouting.decide(try chord("cmd+d"), isRepeat: false, keymap: .standard)

        #expect(decision == .perform(.paneNew))
    }

    @Test func unboundChordPassesThrough() throws {
        #expect(KeyRouting.decide(try chord("cmd+j"), isRepeat: false, keymap: .standard) == .passThrough)
    }

    /// Holding ⌘W must not close pane after pane (and kill their processes).
    @Test func repeatOfStructuralCommandIsSwallowed() throws {
        #expect(KeyRouting.decide(try chord("cmd+w"), isRepeat: true, keymap: .standard) == .swallow)
    }

    @Test(arguments: Direction.allCases)
    func repeatOfResizeAndFocusKeepsPerforming(_ direction: Direction) throws {
        let keymap = Keymap.standard
        let resize = try #require(keymap.chord(for: .paneResize(direction)))
        let focus = try #require(keymap.chord(for: .paneFocus(direction)))

        #expect(KeyRouting.decide(resize, isRepeat: true, keymap: keymap) == .perform(.paneResize(direction)))
        #expect(KeyRouting.decide(focus, isRepeat: true, keymap: keymap) == .perform(.paneFocus(direction)))
    }

    @Test func repeatOfUnboundChordPassesThrough() throws {
        #expect(KeyRouting.decide(try chord("cmd+j"), isRepeat: true, keymap: .standard) == .passThrough)
    }
}
