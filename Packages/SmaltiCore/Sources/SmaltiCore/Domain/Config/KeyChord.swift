public enum KeyModifier: CaseIterable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}

public enum KeyChordError: Error, Equatable, Sendable {
    case unknownModifier(String)
    case unknownKey(String)
    case duplicateModifier(String)
    /// Without ⌘, ⌃ or ⌥ the chord would be plain typing.
    case missingModifier(String)
    case missingKey(String)
}

/// A key plus modifiers. `key` is a single lowercase character or one of `KeyChord.namedKeys`.
///
/// ⇧ is part of the character on a symbol key (`=` is ⇧0 on the Latin American layout, `+` is ⇧= on US), so a chord
/// on a symbol never keeps ⇧: ⌃⌘= is the same chord on every layout. Letters and named keys keep it (⇧⌘A, ⇧⌘←).
public struct KeyChord: Hashable, Sendable {
    public let key: String
    public let modifiers: Set<KeyModifier>

    public init(key: String, modifiers: Set<KeyModifier>) {
        self.key = key
        self.modifiers = Self.isSymbol(key) ? modifiers.subtracting([.shift]) : modifiers
    }

    private static func isSymbol(_ key: String) -> Bool {
        if key == "plus" { return true }
        guard key.count == 1, let character = key.first else { return false }
        return !character.isLetter
    }

    /// Parses `"cmd+opt+d"`, `"ctrl+1"`, `"shift+cmd+="` or `"cmd+opt+left"`.
    public static func parse(_ text: String) throws(KeyChordError) -> KeyChord {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { throw .missingKey(text) }
        guard key.count == 1 || namedKeys.contains(key) else { throw .unknownKey(key) }
        var modifiers: Set<KeyModifier> = []
        for name in parts.dropLast() {
            guard let modifier = modifierNames[name] else { throw .unknownModifier(name) }
            guard modifiers.insert(modifier).inserted else { throw .duplicateModifier(name) }
        }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { throw .missingModifier(text) }
        return KeyChord(key: key, modifiers: modifiers)
    }

    /// Modifiers in Apple's order (⌃⌥⇧⌘) followed by the key, e.g. `⌥⇧⌘←`.
    public var display: String {
        let symbols = Self.displayOrder.filter { modifiers.contains($0.modifier) }.map(\.symbol)
        return symbols.joined() + keySymbol
    }

    /// The key alone as shown: `←`, `⇞`, `K`.
    public var keySymbol: String { Self.namedKeySymbols[key] ?? key.uppercased() }

    /// ⌥ without ⌘ or ⌃ is reserved for typing characters.
    public var usesOptionAlone: Bool {
        modifiers.contains(.option) && !modifiers.contains(.command) && !modifiers.contains(.control)
    }

    private static let namedKeySymbols = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "enter": "↩", "escape": "⎋", "tab": "⇥", "plus": "+",
        "pageup": "⇞", "pagedown": "⇟", "home": "↖", "end": "↘",
    ]
    private static let namedKeys = Set(namedKeySymbols.keys)
    private static let modifierNames: [String: KeyModifier] = [
        "cmd": .command, "command": .command,
        "opt": .option, "option": .option, "alt": .option,
        "ctrl": .control, "control": .control,
        "shift": .shift,
    ]
    private static let displayOrder: [(modifier: KeyModifier, symbol: String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]
}
