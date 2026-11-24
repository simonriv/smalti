import SmaltiCore

/// `[preview]` (spec F5.5): `hover` (boolean). An unwritten key keeps its default.
enum PreviewReader {
    static func read(_ section: TOMLSection) throws(ConfigError) -> PreviewSettings {
        try section.rejectUnknownKeys(allowed: ["hover"])
        var settings = PreviewSettings.standard
        settings.hover = try section.flag("hover") ?? settings.hover
        return settings
    }
}
