import SmaltiCore

/// `[extras]` (spec F7): `otlp` (boolean). An unwritten key keeps its default.
enum ExtrasReader {
    static func read(_ section: TOMLSection) throws(ConfigError) -> ExtrasSettings {
        try section.rejectUnknownKeys(allowed: ["otlp"])
        var settings = ExtrasSettings.standard
        settings.otlp = try section.flag("otlp") ?? settings.otlp
        return settings
    }
}
