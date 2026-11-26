/// One of the welcome card's shortcuts: what it does and its keys in the keymap in effect.
public struct WelcomeShortcut: Equatable, Sendable {
    public let label: String
    public let keys: String
}

/// The welcome card's fixed content (spec F7.7): seven shortcuts read from the keymap, so a chord changed in the TOML
/// shows as changed, and the subtitle naming the palette's chord.
public enum WelcomeContent {
    static let commands: [CommandID] = [
        .paletteOpen, .helpShow, .observatoryToggle, .harnessSearch, .paneNew, .agentJump, .workspaceNew,
    ]

    public static func shortcuts(keymap: Keymap, texts: WelcomeTexts) -> [WelcomeShortcut] {
        commands.map { command in
            WelcomeShortcut(
                label: texts.shortcuts[command] ?? command.rawValue,
                keys: keymap.chord(for: command)?.display ?? texts.inPalette)
        }
    }

    public static func subtitle(keymap: Keymap, texts: WelcomeTexts) -> String {
        texts.subtitle(["palette": keymap.chord(for: .paletteOpen)?.display ?? "⌘K"])
    }
}
