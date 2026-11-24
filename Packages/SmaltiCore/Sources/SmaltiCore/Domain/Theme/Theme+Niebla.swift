// Niebla (light). Board swatch: #eef0f4, #3b5bdb, #2a2e36, #2f9e44; the rest from generate-mockups.py (`THEMES`).
// ANSI darkened from the swatch so every protected color passes 4.5:1 on white; states keep their hue, darker.

extension ThemeColors {
    static let niebla: ThemeColors = {
        var colors = ThemeColors(
            glass: rgb(0xeef0f4), panel: rgb(0xffffff), overlay: rgb(0xf6f7fa), menu: rgb(0xfafbfd),
            hairline: rgb(0x000000), primary: rgb(0x2a2e36), title: rgb(0x1c1f25), secondary: rgb(0x5c6370),
            ghost: rgb(0x8a909b), muted: rgb(0x4a505c), neutralDot: rgb(0x9aa0aa), strong: rgb(0x2f343d),
            kbdText: rgb(0x3d434d), onAccent: rgb(0xffffff), agentTagText: rgb(0xb4532f), accent: rgb(0x3b5bdb),
            ansi: [
                0x2a2e36, 0xc92a2a, 0x237a36, 0x9a5800, 0x3b5bdb, 0x9c36b5, 0x0b7285, 0x868e96,
                0x495057, 0xc2255c, 0x1e7b34, 0x8f5200, 0x364fc7, 0x862e9c, 0x0a6e6e, 0xced4da,
            ].map(rgb),
            working: rgb(0x2f9e44), waiting: rgb(0xc77c02), failed: rgb(0xe03131), stopped: rgb(0x868e96))
        colors.overlayShadowOpacity = 0.18
        colors.menuShadowOpacity = 0.15
        colors.windowShadowOpacity = 0.18
        return colors
    }()
}
