/// What a key press means for Smalti: run a command, eat the key, or let the terminal have it.
public enum KeyRouting: Equatable, Sendable {
    case perform(CommandID)
    /// A held shortcut whose command must not repeat: the key is Smalti's, but nothing happens.
    case swallow
    case passThrough

    /// Auto-repeat only drives commands that are safe to repeat (`CommandID.isRepeatable`); holding ⌘W must not
    /// close pane after pane. The context can leave a command to the terminal (⌘P with the observatory closed) and
    /// limit which commands may run (an open palette lets only ⌘K through, swallowing the rest).
    public static func decide(_ press: KeyPress, keymap: Keymap, context: KeyContext = .unrestricted) -> KeyRouting {
        guard let command = keymap.command(for: press.chord), !context.passingThrough.contains(command) else {
            return .passThrough
        }
        guard context.allowing?.contains(command) ?? true else { return .swallow }
        return !press.isRepeat || command.isRepeatable ? .perform(command) : .swallow
    }
}

/// What the keyboard may do right now.
public struct KeyContext: Equatable, Sendable {
    /// Commands allowed to run; nil allows every shortcut.
    public let allowing: Set<CommandID>?
    /// Commands that are not Smalti's right now: their keys reach the terminal as if unbound.
    public let passingThrough: Set<CommandID>

    public init(allowing: Set<CommandID>? = nil, passingThrough: Set<CommandID> = []) {
        self.allowing = allowing
        self.passingThrough = passingThrough
    }

    public static let unrestricted = KeyContext()

    /// Copy, paste and select all: Smalti commands for the terminal, but a text field's own keys inside an overlay.
    public static let textEditing: Set<CommandID> = [.terminalCopy, .terminalPaste, .terminalSelectAll]

    /// An open overlay (⌘K, ⌃R, the help, feedback): only `allowing` runs, and its text field keeps the text keys.
    public static func overlay(allowing: Set<CommandID>) -> KeyContext {
        KeyContext(allowing: allowing, passingThrough: textEditing)
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
