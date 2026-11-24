/// The four themes of `docs/design/Apariencia.dc.html`, in the board's order; the raw value is the `theme.toml` name.
public enum ThemeID: String, CaseIterable, Sendable {
    case obsidiana
    case niebla
    case ambarNocturno = "ambar-nocturno"
    case bosque

    /// The card title in the Appearance panel.
    public var displayName: String {
        switch self {
        case .obsidiana: "Obsidiana"
        case .niebla: "Niebla"
        case .ambarNocturno: "Ámbar nocturno"
        case .bosque: "Bosque"
        }
    }

    public var isLight: Bool { self == .niebla }

    /// The desktop "Proteger legibilidad" assumes behind the glass: the worst one for the theme.
    public var worstBackdrop: Backdrop { isLight ? .black : .white }

    /// ANSI indices meant as backgrounds, which protection leaves alone (spec F5).
    var backgroundPair: Set<Int> { isLight ? [7, 15] : [0, 8] }
}
