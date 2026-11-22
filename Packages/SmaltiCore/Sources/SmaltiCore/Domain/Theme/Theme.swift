/// Visual tokens shared by the window chrome and the terminal engine.
public struct Theme: Equatable, Sendable {
    public let name: String
    public let window: WindowTokens
    public let panel: PanelTokens
    public let chrome: ChromeTokens
    public let text: TextTokens
    public let accent: RGBAColor
    public let terminal: TerminalAppearance
}

public struct WindowTokens: Equatable, Sendable {
    public let background: RGBAColor
    public let blurRadius: Double
    public let border: RGBAColor
    public let cornerRadius: Double
}

public struct PanelTokens: Equatable, Sendable {
    public let background: RGBAColor
    public let border: RGBAColor
    public let cornerRadius: Double
    public let gap: Double
    public let areaPadding: Double
}

public struct ChromeTokens: Equatable, Sendable {
    public let topStripHeight: Double
}

public struct TextTokens: Equatable, Sendable {
    public let primary: RGBAColor
    public let title: RGBAColor
    public let secondary: RGBAColor
}

public struct TerminalAppearance: Equatable, Sendable {
    public let fontFamily: String
    public let fontSize: Double
    public let lineHeight: Double
    public let foreground: RGBAColor
    public let cursor: RGBAColor
    /// The 16 ANSI colors, normal 0–7 then bright 8–15.
    public let palette: [RGBAColor]
    public let paddingX: Double
    public let paddingY: Double
}
