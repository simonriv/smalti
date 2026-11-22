/// What a key press means for Smalti: run a command, eat the key, or let the terminal have it.
public enum KeyRouting: Equatable, Sendable {
    case perform(CommandID)
    /// A held shortcut whose command must not repeat: the key is Smalti's, but nothing happens.
    case swallow
    case passThrough

    /// Auto-repeat only drives commands that are safe to repeat (`CommandID.isRepeatable`); holding ⌘W must not
    /// close pane after pane.
    public static func decide(_ chord: KeyChord, isRepeat: Bool, keymap: Keymap) -> KeyRouting {
        guard let command = keymap.command(for: chord) else { return .passThrough }
        return !isRepeat || command.isRepeatable ? .perform(command) : .swallow
    }
}

extension CommandID {
    /// Moving focus and resizing step in small increments, so holding the shortcut keeps going.
    public var isRepeatable: Bool {
        Direction.allCases.contains { self == .paneFocus($0) || self == .paneResize($0) }
    }
}
