/// Which chord triggers which command. One chord per command, one command per chord.
public struct Keymap: Sendable, Equatable {
    private let commandsByChord: [KeyChord: CommandID]

    private init(commandsByChord: [KeyChord: CommandID]) {
        self.commandsByChord = commandsByChord
    }

    var bindings: [KeyChord: CommandID] { commandsByChord }

    public static let standard = Keymap(commandsByChord: standardBindings)

    public func command(for chord: KeyChord) -> CommandID? {
        commandsByChord[chord]
    }

    public func chord(for command: CommandID) -> KeyChord? {
        commandsByChord.first { $0.value == command }?.key
    }

    /// A copy with `bindings` applied: a command replaces, `nil` unbinds the chord. Binding a command to a new
    /// chord releases its previous one. `file` and `line` of the error are left for the config reader to fill.
    public func overriding(_ bindings: [KeyChord: CommandID?]) throws(ConfigError) -> Keymap {
        var updated = commandsByChord
        for (chord, command) in bindings.sorted(by: { $0.key.display < $1.key.display }) {
            try Self.validate(chord)
            updated[chord] = nil
            guard let command else { continue }
            updated = updated.filter { $0.value != command }
            updated[chord] = command
        }
        return Keymap(commandsByChord: updated)
    }

    /// Rejects a chord no keymap may bind: ⌥ without ⌘ or ⌃ (R8). `file` and `line` are left for the config reader.
    public static func validate(_ chord: KeyChord) throws(ConfigError) {
        guard chord.usesOptionAlone else { return }
        throw ConfigError(
            file: "", line: nil, key: chord.display, reason: "⌥ sin ⌘ ni ⌃ queda reservado para escribir")
    }

    private static let standardBindings: [KeyChord: CommandID] = {
        var bindings: [KeyChord: CommandID] = [
            chord("k", .command): .paletteOpen,
            chord("d", .command, .option): .layoutDwindle,
            chord("c", .command, .option): .layoutColumns,
            chord("m", .command, .option): .layoutMaster,
            chord("=", .shift, .command): .panesEqualize,
            chord("d", .command): .paneNew,
            chord("w", .command): .paneClose,
            chord("n", .control, .command): .workspaceNew,
        ]
        for number in CommandID.digits {
            bindings[chord(String(number), .command)] = .paneFocus(number)
            bindings[chord(String(number), .control)] = .workspace(number)
        }
        for direction in Direction.allCases {
            bindings[chord(direction.name, .command, .option)] = .paneFocus(direction)
            bindings[chord(direction.name, .shift, .command, .option)] = .paneSwap(direction)
            bindings[chord(direction.name, .control, .command, .option)] = .paneResize(direction)
        }
        return bindings
    }()

    private static func chord(_ key: String, _ modifiers: KeyModifier...) -> KeyChord {
        KeyChord(key: key, modifiers: Set(modifiers))
    }
}
