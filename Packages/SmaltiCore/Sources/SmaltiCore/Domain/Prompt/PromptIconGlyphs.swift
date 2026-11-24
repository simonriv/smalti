extension PromptIcons {
    /// First code point of `SmaltiSymbols`; its glyphs follow `PromptIcon.allCases` (spec F5: U+E900–U+E91F).
    static let thinBase: UInt32 = 0xE900

    /// Nerd Font glyphs, the same as Starship's "Nerd Font Symbols" preset where one exists.
    private static let nerdGlyphs: [PromptIcon: Character] = [
        .folder: "\u{F07B}", .branch: "\u{E0A0}", .node: "\u{E718}", .bun: "\u{E76F}", .python: "\u{E73C}",
        .go: "\u{E626}", .clock: "\u{F017}", .kubernetes: "\u{F10FE}", .cloud: "\u{F0C2}",
    ]

    /// The character that draws `icon` with this set, or `nil` for "Sin iconos".
    public func character(for icon: PromptIcon) -> Character? {
        switch self {
        case .thin: Self.thinCharacter(for: icon)
        case .nerd: Self.nerdGlyphs[icon]
        case .none: nil
        }
    }

    private static func thinCharacter(for icon: PromptIcon) -> Character? {
        let index = UInt32(PromptIcon.allCases.firstIndex(of: icon) ?? 0)
        return Unicode.Scalar(thinBase + index).map(Character.init)
    }
}
