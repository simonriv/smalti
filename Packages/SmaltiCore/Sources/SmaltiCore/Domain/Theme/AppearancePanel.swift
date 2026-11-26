/// Texts of the Appearance panel (`Apariencia.dc.html`) that depend on values.
public enum AppearanceTexts {
    /// "62%", or "62% · 66% bajo el texto" when "Proteger legibilidad" raised the panels.
    public static func opacity(chosen: Double, underText: Double, copy: AppearanceCopy) -> String {
        let chosenText = percent(chosen)
        let underTextText = percent(underText)
        return underTextText == chosenText
            ? chosenText : copy.underText(["chosen": chosenText, "under": underTextText])
    }

    public static func blur(_ pixels: Double) -> String { pixelsText(pixels) }
    public static func gap(_ pixels: Double) -> String { pixelsText(pixels) }
    public static func radius(_ pixels: Double) -> String { pixelsText(pixels) }

    public static func font(family: String, size: Double) -> String { "\(family) \(number(size))" }

    /// Spec F5 (Claude): how many ANSI colors protection moved; nothing when none.
    public static func adjusted(_ count: Int, copy: AppearanceCopy) -> String? {
        count == 0 ? nil : copy.adjusted(count)
    }

    /// "se guarda en ~/.config/…/theme.toml": the real path, with the home as `~` and the middle folders elided.
    public static func savedIn(path: String, home: String, copy: AppearanceCopy) -> String {
        copy.savedIn(["path": shortened(path, home: home)])
    }

    private static let maximumWholeComponents = 2

    private static func shortened(_ path: String, home: String) -> String {
        let isInHome = path.hasPrefix(home + "/")
        let relative = isInHome ? String(path.dropFirst(home.count + 1)) : String(path.drop { $0 == "/" })
        let root = isInHome ? "~/" : "/"
        let components = relative.split(separator: "/").map(String.init)
        guard components.count > maximumWholeComponents, let first = components.first, let last = components.last
        else { return root + relative }
        return root + first + "/…/" + last
    }

    private static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
    private static func pixelsText(_ value: Double) -> String { "\(number(value)) px" }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// The four colors of a theme card's preview (`Apariencia.dc.html`): background and three bars.
public struct ThemeSwatch: Equatable, Sendable {
    public let background: RGBAColor
    public let accent: RGBAColor
    public let text: RGBAColor
    public let green: RGBAColor

    public init(background: RGBAColor, accent: RGBAColor, text: RGBAColor, green: RGBAColor) {
        self.background = background
        self.accent = accent
        self.text = text
        self.green = green
    }
}

extension ThemeID {
    /// The board's card colors, as drawn there.
    public var swatch: ThemeSwatch {
        switch self {
        case .obsidiana:
            ThemeSwatch(background: rgb(0x12141b), accent: rgb(0x7aa2f7), text: rgb(0xc3c7cf), green: rgb(0x9ece6a))
        case .niebla:
            ThemeSwatch(background: rgb(0xeef0f4), accent: rgb(0x3b5bdb), text: rgb(0x2a2e36), green: rgb(0x2f9e44))
        case .ambarNocturno:
            ThemeSwatch(background: rgb(0x1a1410), accent: rgb(0xe0af68), text: rgb(0xe8dccb), green: rgb(0xb5c97a))
        case .bosque:
            ThemeSwatch(background: rgb(0x0f1714), accent: rgb(0x6fd3b5), text: rgb(0xcfe0d8), green: rgb(0xa6d86b))
        }
    }

    /// "· claro" after Niebla's name on its card.
    public var cardNote: String? { isLight ? "· claro" : nil }

    /// "Siguiente tema": the board's order, back to the first after the last.
    public var next: ThemeID {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? all.startIndex
        return all[(index + 1) % all.count]
    }
}

extension AppearanceSettings {
    /// Spec F5: what the sliders and steppers allow, the same bounds the TOML reader checks.
    public static let glassOpacityRange: ClosedRange<Double> = 0.3...0.95
    public static let blurRange: ClosedRange<Double> = 0...48
    public static let fontSizeRange: ClosedRange<Double> = 6...72
    public static let gapRange: ClosedRange<Double> = 0...32
    public static let radiusRange: ClosedRange<Double> = 0...32

    public static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension AppearanceDocument {
    /// An ANSI color picked in the panel: stored as a difference from the current theme (`[appearance.ansi.<tema>]`).
    public mutating func setANSI(_ index: Int, to color: RGBAColor) throws(ColorError) {
        let theme = appearance.theme
        let current = appearance.ansiOverrides[theme] ?? .none
        appearance.ansiOverrides[theme] = current.merging(try ANSIOverrides([index: color]))
    }

    /// "Restablecer paleta ANSI": the current theme's colors again; other themes keep their edits.
    public mutating func resetANSI() {
        appearance.ansiOverrides[appearance.theme] = nil
    }
}
