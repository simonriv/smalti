/// What a key press means for Smalti: run a command, eat the key, or let the terminal have it.
public enum KeyRouting: Equatable, Sendable {
    case perform(CommandID)
    /// A held shortcut whose command must not repeat: the key is Smalti's, but nothing happens.
    case swallow
    case passThrough

    /// Auto-repeat only drives commands that are safe to repeat (`CommandID.isRepeatable`); holding ⌘W must not
    /// close pane after pane. `allowing`, when given, limits which commands may run (an open palette lets only ⌘K
    /// through); other Smalti shortcuts are swallowed so they never act behind it.
    public static func decide(_ press: KeyPress, keymap: Keymap, allowing: Set<CommandID>? = nil) -> KeyRouting {
        guard let command = keymap.command(for: press.chord) else { return .passThrough }
        guard allowing?.contains(command) ?? true else { return .swallow }
        return !press.isRepeat || command.isRepeatable ? .perform(command) : .swallow
    }
}

/// One key press as routing sees it.
public struct KeyPress: Equatable, Sendable {
    public let chord: KeyChord
    /// The key is held down and the system is repeating it.
    public let isRepeat: Bool

    public init(_ chord: KeyChord, isRepeat: Bool = false) {
        self.chord = chord
        self.isRepeat = isRepeat
    }
}

extension CommandID {
    /// Moving focus and resizing step in small increments, so holding the shortcut keeps going.
    public var isRepeatable: Bool {
        Direction.allCases.contains { self == .paneFocus($0) || self == .paneResize($0) }
    }
}
