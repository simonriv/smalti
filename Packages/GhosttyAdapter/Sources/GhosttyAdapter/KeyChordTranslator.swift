import AppKit
import SmaltiCore

/// Turns a key event into the `KeyChord` Smalti's keymap speaks. Characters come from
/// `charactersIgnoringModifiers`, which ignores every modifier except ⇧: on the Latin American layout ⇧0 arrives as
/// "=" with ⇧, and `KeyChord` drops that ⇧ on symbols, so ⌃⌘= matches on every layout. ⌥ never changes the key
/// (⌥Q stays "q", not "@").
public enum KeyChordTranslator {
    public static func chord(from event: NSEvent) -> KeyChord? {
        chord(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
    }

    static func chord(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> KeyChord? {
        guard let key = namedKeys[keyCode] ?? characterKey(characters) else { return nil }
        return KeyChord(key: key, modifiers: chordModifiers(modifiers))
    }

    /// Keys whose characters are private-use or control codes; the key code identifies them on every layout.
    private static let namedKeys: [UInt16: String] = [
        123: "left", 124: "right", 125: "down", 126: "up", 36: "enter", 76: "enter", 53: "escape", 48: "tab",
        116: "pageup", 121: "pagedown", 115: "home", 119: "end",
    ]

    private static func characterKey(_ characters: String?) -> String? {
        guard let characters, characters.count == 1 else { return nil }
        let key = characters.lowercased()
        return key == "+" ? "plus" : key
    }

    private static func chordModifiers(_ flags: NSEvent.ModifierFlags) -> Set<KeyModifier> {
        let mapping: [(NSEvent.ModifierFlags, KeyModifier)] = [
            (.command, .command), (.option, .option), (.control, .control), (.shift, .shift),
        ]
        return Set(mapping.compactMap { flags.contains($0.0) ? $0.1 : nil })
    }
}
