/// The colors of one theme. Opaque colors: `Theme.make` applies the design's opacities (glass 0.62, panel 0.34,
/// overlay 0.82, menu 0.94) and draws hairlines from `hairline` with their own alphas.
struct ThemeColors: Equatable, Sendable {
    let glass: RGBAColor
    let panel: RGBAColor
    /// The ⌘K box and the overlays that reuse it.
    let overlay: RGBAColor
    /// The completion menu.
    let menu: RGBAColor
    /// White on dark themes, black on Niebla.
    let hairline: RGBAColor
    let primary: RGBAColor
    let title: RGBAColor
    let secondary: RGBAColor
    let ghost: RGBAColor
    /// Inactive workspace names and pane directories.
    let muted: RGBAColor
    /// Status dot before an agent has a state.
    let neutralDot: RGBAColor
    /// Emphasized secondary text (`hoy …` figures, observatory pills, program tags).
    let strong: RGBAColor
    let kbdText: RGBAColor
    /// Text on an accent-filled button.
    let onAccent: RGBAColor
    let agentTagText: RGBAColor
    let accent: RGBAColor
    /// The 16 ANSI colors, normal 0–7 then bright 8–15.
    let ansi: [RGBAColor]
    let working: RGBAColor
    let waiting: RGBAColor
    let failed: RGBAColor
    let stopped: RGBAColor
    /// Black shadow under the ⌘K box and under the completion menu; softer on the light theme.
    var overlayShadowOpacity = 0.55
    var menuShadowOpacity = 0.45
}

/// `0xrrggbb` as an opaque color.
func rgb(_ value: UInt32) -> RGBAColor {
    RGBAColor(
        red: UInt8(truncatingIfNeeded: value >> 16),
        green: UInt8(truncatingIfNeeded: value >> 8),
        blue: UInt8(truncatingIfNeeded: value),
        alpha: 1)
}

extension ThemeColors {
    static let obsidiana = ThemeColors(
        glass: rgb(0x0d0f15), panel: rgb(0x06070a), overlay: rgb(0x14161e), menu: rgb(0x12141b),
        hairline: rgb(0xffffff), primary: rgb(0xd7dae0), title: rgb(0xe6e9ef), secondary: rgb(0x8b919c),
        ghost: rgb(0x5f6672), muted: rgb(0x9aa0ab), neutralDot: rgb(0x565c68), strong: rgb(0xc3c7cf),
        kbdText: rgb(0xaeb3bd), onAccent: rgb(0x0d0f15), agentTagText: rgb(0xf0a98f), accent: rgb(0x7aa2f7),
        ansi: [
            0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6,
            0x414868, 0xff99ad, 0xb9f27c, 0xffc777, 0xa3bdfa, 0xd3b8ff, 0xa4e3ff, 0xc0caf5,
        ].map(rgb),
        working: rgb(0x9ece6a), waiting: rgb(0xe0af68), failed: rgb(0xf7768e), stopped: rgb(0x6b717c))
}
