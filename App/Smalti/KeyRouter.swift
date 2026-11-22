import AppKit
import GhosttyAdapter
import SmaltiCore

/// Primary adapter for the keyboard: a Smalti shortcut becomes a command; anything else reaches the terminal intact
/// (the engine's own bindings are cleared, R6). ⌥ alone is never a Smalti shortcut, so ⌥ characters always pass.
@MainActor
struct KeyRouter {
    let keymap: () -> Keymap
    /// Commands allowed right now; nil allows every shortcut (see `KeyRouting.decide`).
    let allowing: () -> Set<CommandID>?
    let perform: (CommandID) -> Void

    /// True when the key belongs to Smalti and must not reach the terminal.
    func route(_ event: NSEvent, composing: Bool) -> Bool {
        // A pending dead key or IME composition owns the next key; switching panes would strand it.
        guard event.type == .keyDown, !composing, let chord = KeyChordTranslator.chord(from: event) else {
            return false
        }
        switch KeyRouting.decide(KeyPress(chord, isRepeat: event.isARepeat), keymap: keymap(), allowing: allowing()) {
        case .perform(let command):
            perform(command)
            return true
        case .swallow: return true
        case .passThrough: return false
        }
    }
}
