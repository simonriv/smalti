// Bosque. Board swatch: #0f1714, #6fd3b5, #cfe0d8, #a6d86b; the rest from generate-mockups.py (`THEMES`).

extension ThemeColors {
    static let bosque = ThemeColors(
        glass: rgb(0x0f1714), panel: rgb(0x060a08), overlay: rgb(0x161f1b), menu: rgb(0x131c18),
        hairline: rgb(0xdcfff0), primary: rgb(0xcfe0d8), title: rgb(0xe2efe9), secondary: rgb(0x8a9c94),
        ghost: rgb(0x5a6b63), muted: rgb(0x9aaca4), neutralDot: rgb(0x56665f), strong: rgb(0xbfd0c8),
        kbdText: rgb(0xaebfb7), onAccent: rgb(0x0f1714), agentTagText: rgb(0xf0a98f), accent: rgb(0x6fd3b5),
        ansi: [
            0x141e1a, 0xec7f86, 0xa6d86b, 0xe3c06f, 0x74b3e0, 0xb99be0, 0x6fd3b5, 0xb9cbc2,
            0x3c4f47, 0xf59ca2, 0xbde68a, 0xeed28e, 0x95c8ee, 0xceb5ee, 0x92e2ca, 0xe2efe9,
        ].map(rgb),
        working: rgb(0xa6d86b), waiting: rgb(0xe3c06f), failed: rgb(0xec7f86), stopped: rgb(0x62746c))
}
