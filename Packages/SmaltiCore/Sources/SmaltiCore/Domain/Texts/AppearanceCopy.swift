/// F7.7: the Appearance panel's words that depend on values, and the themes' names.
public struct AppearanceCopy: Sendable, Equatable {
    public let underText: TextTemplate
    public let adjusted: PluralText
    public let savedIn: TextTemplate
    public let themeNames: [ThemeID: String]

    public static let spanish = AppearanceCopy(
        underText: "{chosen} · {under} bajo el texto",
        adjusted: PluralText(
            one: "Ajustados por legibilidad: {count} color", other: "Ajustados por legibilidad: {count} colores"),
        savedIn: "se guarda en {path}",
        themeNames: [.obsidiana: "Obsidiana", .niebla: "Niebla", .ambarNocturno: "Ámbar nocturno", .bosque: "Bosque"])

    public static let english = AppearanceCopy(
        underText: "{chosen} · {under} under the text",
        adjusted: PluralText(
            one: "Adjusted for legibility: {count} color", other: "Adjusted for legibility: {count} colors"),
        savedIn: "saved in {path}",
        themeNames: [.obsidiana: "Obsidian", .niebla: "Mist", .ambarNocturno: "Night Amber", .bosque: "Forest"])
}
