import SmaltiCore

/// Renders Smalti's terminal appearance as a libghostty config file.
public enum GhosttyConfigText {
    /// JetBrains Mono's natural line height in em: (ascender 1020 + |descender| 300 + line gap 0) / 1000 units.
    /// libghostty's cell height starts there; `adjust-cell-height` adds the rest of the theme's line height.
    static let naturalLineHeight = 1.32

    /// Percentage that turns the font's natural line height into `lineHeight` (1.62 → "23%"; measured in the F0
    /// spike at 21.0 pt against the design's 21.06 pt).
    static func cellHeightAdjustment(lineHeight: Double) -> String {
        "\(Int(((lineHeight / naturalLineHeight - 1) * 100).rounded()))%"
    }

    /// libghostty's default bindings (⌘K clear_screen, ⌘D new_split, ⌘1…9 goto_tab, ⌘W close_surface…) would take
    /// Smalti's own shortcuts before the `KeyRouter` sees them (R6), so they are cleared and only copy and paste,
    /// which need the terminal's selection, come back.
    static let keybinds = [
        "keybind = clear",
        "keybind = super+c=copy_to_clipboard",
        "keybind = super+v=paste_from_clipboard",
    ]

    public static func render(_ appearance: TerminalAppearance) -> String {
        let settings = [
            "font-family = \"\(appearance.fontFamily)\"",
            "font-size = \(number(appearance.fontSize))",
            "adjust-cell-height = \(cellHeightAdjustment(lineHeight: appearance.lineHeight))",
            "foreground = \(hex(appearance.foreground))",
            "cursor-color = \(hex(appearance.cursor))",
            // The pane container paints the panel background; the surface stays transparent over the glass.
            "background-opacity = 0",
            "window-padding-x = \(number(appearance.paddingX))",
            "window-padding-y = \(number(appearance.paddingY))",
            "window-padding-balance = false",
            // ⌥ composes characters on the Latin American layout (@, |, #…), so it must not act as Meta.
            "macos-option-as-alt = false",
            "shell-integration = zsh",
            "confirm-close-surface = false",
        ]
        let palette = appearance.palette.enumerated().map { index, color in "palette = \(index)=\(hex(color))" }
        return (keybinds + settings + palette).joined(separator: "\n") + "\n"
    }

    private static func hex(_ color: RGBAColor) -> String {
        "#"
            + [color.red, color.green, color.blue].map { byte in
                let digits = String(byte, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
