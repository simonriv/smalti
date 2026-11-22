import SmaltiCore

/// Renders Smalti's terminal appearance as a libghostty config file.
public enum GhosttyConfigText {
    /// Extra cell height over JetBrains Mono's natural line height to approach the design's 1.62 line height.
    /// Starting value; calibrated against Main.dc.html in the F0 spike.
    static let cellHeightAdjustment = "23%"

    public static func render(_ appearance: TerminalAppearance) -> String {
        let settings = [
            "font-family = \"\(appearance.fontFamily)\"",
            "font-size = \(number(appearance.fontSize))",
            "adjust-cell-height = \(cellHeightAdjustment)",
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
        return (settings + palette).joined(separator: "\n") + "\n"
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
