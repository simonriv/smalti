import SmaltiCore

/// `starship.toml` as text (spec F5, "Exportar como starship.toml").
public enum StarshipText {
    public static func render(_ preset: StarshipPreset) -> String {
        let header = ["# Generado por Smalti (Estudio de prompt)."] + preset.comments.map { "# " + $0 }
        let top = preset.settings.map(entry) + ["format = " + TOMLWriter.string(preset.format)]
        let tables = preset.tables.map { table in ["", "[\(table.name)]"] + table.entries.map(entry) }.flatMap { $0 }
        return (header + [""] + top + tables).joined(separator: "\n") + "\n"
    }

    private static func entry(_ entry: StarshipEntry) -> String {
        "\(entry.key) = " + value(entry.value)
    }

    private static func value(_ value: StarshipValue) -> String {
        switch value {
        case .string(let text): TOMLWriter.string(text)
        case .integer(let number): String(number)
        case .boolean(let flag): String(flag)
        }
    }
}
