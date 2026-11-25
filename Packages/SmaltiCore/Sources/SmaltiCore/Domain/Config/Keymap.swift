/// Which chords trigger which command. One command per chord; a command may have several chords (F4.5: ⌘+ arrives
/// differently on each layout). The first chord of a command is its primary, the one menus and the help show.
public struct Keymap: Sendable, Equatable {
    /// Chord → command, in insertion order: defaults first, then the user's aliases.
    private let entries: [(chord: KeyChord, command: CommandID)]

    private init(entries: [(chord: KeyChord, command: CommandID)]) {
        self.entries = entries
    }

    public static func == (lhs: Keymap, rhs: Keymap) -> Bool {
        lhs.entries.elementsEqual(rhs.entries) { $0.chord == $1.chord && $0.command == $1.command }
    }

    var bindings: [KeyChord: CommandID] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.chord, $0.command) })
    }

    public static let standard = Keymap(entries: standardEntries)

    public func command(for chord: KeyChord) -> CommandID? {
        entries.first { $0.chord == chord }?.command
    }

    /// Every chord of `command`, primary first.
    public func chords(for command: CommandID) -> [KeyChord] {
        entries.filter { $0.command == command }.map(\.chord)
    }

    /// The primary chord: the one menus and the help show.
    public func chord(for command: CommandID) -> KeyChord? {
        entries.first { $0.command == command }?.chord
    }

    /// A copy with `bindings` applied, sorted by display (the order a dictionary cannot keep).
    public func overriding(_ bindings: [KeyChord: CommandID?]) throws(ConfigError) -> Keymap {
        try overriding(ordered: bindings.sorted { $0.key.display < $1.key.display }.map { ($0.key, $0.value) })
    }

    /// A copy with `bindings` applied in their order (the TOML file's): the chords written for a command replace its
    /// own, the first written becoming its primary, and are taken from whichever command had them; `nil` unbinds the
    /// chord. `file` and `line` of the error are left for the config reader to fill.
    public func overriding(ordered bindings: [(chord: KeyChord, command: CommandID?)]) throws(ConfigError) -> Keymap {
        for binding in bindings { try Self.validate(binding.chord) }
        let rebound = Set(bindings.compactMap(\.command))
        let written = Set(bindings.map(\.chord))
        var updated = entries.filter { !rebound.contains($0.command) && !written.contains($0.chord) }
        for case let (chord, command?) in bindings {
            updated.removeAll { $0.chord == chord }
            updated.append((chord, command))
        }
        return Keymap(entries: updated)
    }

    /// Rejects a chord no keymap may bind: ⌥ without ⌘ or ⌃ (R8). `file` and `line` are left for the config reader.
    public static func validate(_ chord: KeyChord) throws(ConfigError) {
        guard chord.usesOptionAlone else { return }
        throw ConfigError(
            file: "", line: nil, key: chord.display, reason: "⌥ sin ⌘ ni ⌃ queda reservado para escribir")
    }

    /// Ordered: for a command with several chords, the first listed is its primary.
    private static let standardEntries: [(chord: KeyChord, command: CommandID)] = {
        var entries: [(chord: KeyChord, command: CommandID)] = [
            (chord("k", .command), .paletteOpen),
            (chord("d", .command, .option), .layoutDwindle),
            (chord("c", .command, .option), .layoutColumns),
            (chord("m", .command, .option), .layoutMaster),
            (chord("=", .control, .command), .panesEqualize),
            (chord("d", .command), .paneNew),
            (chord("w", .command), .paneClose),
            (chord("n", .control, .command), .workspaceNew),
            (chord("j", .command), .agentJump),
            (chord("a", .shift, .command), .observatoryToggle),
            (chord("o", .shift, .command), .harnessSearch),
            (chord("e", .shift, .command), .editorOpenBeside),
            (chord("l", .shift, .command), .editorOpenLastEdited),
            (chord("f", .shift, .command), .observatoryFilter),
            (chord("p", .command), .observatoryPeriod),
            (chord("enter", .shift, .command), .guardApprove),
            (chord("escape", .shift, .command), .guardReject),
        ]
        entries += basicEntries
        for number in NumberedShortcuts.range {
            entries.append((chord(String(number), .command), .paneFocus(number)))
            entries.append((chord(String(number), .control), .workspace(number)))
        }
        for direction in Direction.allCases {
            entries.append((chord(direction.name, .command, .option), .paneFocus(direction)))
            entries.append((chord(direction.name, .shift, .command, .option), .paneSwap(direction)))
            entries.append((chord(direction.name, .control, .command, .option), .paneResize(direction)))
        }
        return entries
    }()

    /// F4.5. ⌘+ is `plus` on every layout (⇧ belongs to the character, see `KeyChord`); ⌘= is Ghostty's own alias.
    private static let basicEntries: [(chord: KeyChord, command: CommandID)] = [
        (chord("n", .command), .windowNew),
        (chord("w", .shift, .command), .windowClose),
        (chord("f", .control, .command), .windowFullscreen),
        (chord("m", .command), .windowMinimize),
        (chord("?", .command), .helpShow),
        // F5: ⌘, is Settings on macOS, so it opens Apariencia; the TOML moves to ⌥⌘,.
        (chord(",", .command), .appearanceOpen),
        (chord(",", .option, .command), .configOpen),
        (chord("p", .shift, .command), .promptStudio),
        // F5.5: Finder's Quick Look key; space belongs to the shell.
        (chord("y", .command), .previewQuickLook),
        (chord("c", .command), .terminalCopy),
        (chord("v", .command), .terminalPaste),
        (chord("a", .command), .terminalSelectAll),
        (chord("l", .command), .terminalClear),
        (chord("f", .command), .searchOpen),
        (chord("g", .command), .searchNext),
        (chord("g", .shift, .command), .searchPrevious),
        (chord("plus", .command), .fontIncrease),
        (chord("=", .command), .fontIncrease),
        (chord("-", .command), .fontDecrease),
        (chord("0", .command), .fontReset),
        (chord("pageup", .command), .scrollPageUp),
        (chord("pagedown", .command), .scrollPageDown),
        (chord("home", .command), .scrollTop),
        (chord("end", .command), .scrollBottom),
        (chord("up", .command), .promptPrevious),
        (chord("down", .command), .promptNext),
    ]

    private static func chord(_ key: String, _ modifiers: KeyModifier...) -> KeyChord {
        KeyChord(key: key, modifiers: Set(modifiers))
    }
}
