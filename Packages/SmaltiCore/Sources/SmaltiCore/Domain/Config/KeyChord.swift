public enum KeyModifier: CaseIterable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}

public enum KeyChordError: Error, Equatable, Sendable {
    case unknownModifier(String)
    case unknownKey(String)
    case missingKey(String)
}

/// A key plus modifiers. `key` is a single lowercase character or one of `KeyChord.namedKeys`.
public struct KeyChord: Hashable, Sendable {
    public let key: String
    public let modifiers: Set<KeyModifier>

    public init(key: String, modifiers: Set<KeyModifier>) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses `"cmd+opt+d"`, `"ctrl+1"`, `"shift+cmd+="` or `"cmd+opt+left"`.
    public static func parse(_ text: String) throws(KeyChordError) -> KeyChord {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { throw .missingKey(text) }
        guard key.count == 1 || namedKeys.contains(key) else { throw .unknownKey(key) }
        var modifiers: Set<KeyModifier> = []
        for name in parts.dropLast() {
            guard let modifier = modifierNames[name] else { throw .unknownModifier(name) }
            modifiers.insert(modifier)
        }
        return KeyChord(key: key, modifiers: modifiers)
    }

    /// Modifiers in Apple's order (⌃⌥⇧⌘) followed by the key, e.g. `⌥⇧⌘←`.
    public var display: String {
        let symbols = Self.displayOrder.filter { modifiers.contains($0.modifier) }.map(\.symbol)
        return symbols.joined() + (Self.namedKeySymbols[key] ?? key.uppercased())
    }

    /// ⌥ without ⌘ or ⌃ is reserved for typing characters.
    public var usesOptionAlone: Bool {
        modifiers.contains(.option) && !modifiers.contains(.command) && !modifiers.contains(.control)
    }

    private static let namedKeySymbols = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "enter": "↩", "escape": "⎋", "tab": "⇥",
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
