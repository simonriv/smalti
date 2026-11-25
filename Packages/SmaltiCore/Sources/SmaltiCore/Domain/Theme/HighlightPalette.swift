/// The colors of the command line's highlight roles in a theme (spec F5.6, "Colores"): ANSI 4, error, ANSI 6,
/// ANSI 5 (options and variables), ANSI 2 and secondary text. Paths are underlined in the color they already have.
public struct HighlightPalette: Equatable, Sendable {
    public let command: RGBAColor
    public let unknown: RGBAColor
    public let subcommand: RGBAColor
    public let option: RGBAColor
    public let string: RGBAColor
    public let `operator`: RGBAColor
}

extension Theme {
    private static let commandANSI = 4
    private static let subcommandANSI = 6
    private static let optionANSI = 5
    private static let stringANSI = 2

    /// With "Proteger legibilidad" each color reaches 4.5:1 over the protected panel, like the prompt's segments
    /// (without their pill passes: the line has no pills).
    public var highlightPalette: HighlightPalette {
        HighlightPalette(
            command: protectedColor(for: .ansi(Self.commandANSI)), unknown: protectedColor(for: .failed),
            subcommand: protectedColor(for: .ansi(Self.subcommandANSI)),
            option: protectedColor(for: .ansi(Self.optionANSI)), string: protectedColor(for: .ansi(Self.stringANSI)),
            operator: protectedColor(for: .secondary))
    }
}
