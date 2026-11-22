import AppKit
import GhosttyAdapter
import SmaltiCore

/// Primary adapter for the keyboard: a Smalti shortcut becomes a command; anything else reaches the terminal intact
/// (the engine's own bindings are cleared, R6). ⌥ alone is never a Smalti shortcut, so ⌥ characters always pass.
@MainActor
struct KeyRouter {
    let keymap: () -> Keymap
    let perform: (CommandID) -> Void

    /// True when the event was a Smalti shortcut and must not reach the terminal.
    func route(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let chord = KeyChordTranslator.chord(from: event),
            let command = keymap().command(for: chord)
        else { return false }
        perform(command)
        return true
    }
}
