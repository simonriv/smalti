// Ámbar nocturno. Board swatch: #1a1410, #e0af68, #e8dccb, #b5c97a; the rest from generate-mockups.py (`THEMES`).

extension ThemeColors {
    static let ambarNocturno = ThemeColors(
        glass: rgb(0x1a1410), panel: rgb(0x0c0907), overlay: rgb(0x221b16), menu: rgb(0x1f1914),
        hairline: rgb(0xfff0dc), primary: rgb(0xe8dccb), title: rgb(0xf2e8da), secondary: rgb(0xa39582),
        ghost: rgb(0x6e6355), muted: rgb(0xb0a391), neutralDot: rgb(0x6a6052), strong: rgb(0xd2c6b5),
        kbdText: rgb(0xc2b6a5), onAccent: rgb(0x1a1410), agentTagText: rgb(0xf0a98f), accent: rgb(0xe0af68),
        ansi: [
            0x1f1914, 0xe8826f, 0xb5c97a, 0xe0af68, 0x8fa8c8, 0xc79bc0, 0x8cc4b8, 0xd8ccb9,
            0x4a3f33, 0xf29c8a, 0xc9db92, 0xf0c88a, 0xa9bfdb, 0xdab3d4, 0xa6d7cc, 0xf2e8da,
        ].map(rgb),
        working: rgb(0xb5c97a), waiting: rgb(0xe0af68), failed: rgb(0xe8826f), stopped: rgb(0x7a6e60))
}
