import SmaltiCore

/// `[input]`: `enabled`, `predictions`, `completions` (booleans), `history_limit` and `generator_timeout_ms`
/// (integers within `InputSettings`' ranges). Unwritten keys keep their defaults.
enum InputReader {
    private static let flags = ["enabled", "predictions", "completions"]
    private static let historyLimitKey = "history_limit"
    private static let timeoutKey = "generator_timeout_ms"

    static func read(_ section: TOMLSection) throws(ConfigError) -> InputSettings {
        try section.rejectUnknownKeys(allowed: Set(flags + [historyLimitKey, timeoutKey]))
        var settings = InputSettings.standard
        settings.isEnabled = try section.flag("enabled") ?? settings.isEnabled
        settings.hasPredictions = try section.flag("predictions") ?? settings.hasPredictions
        settings.hasCompletions = try section.flag("completions") ?? settings.hasCompletions
        if let limit = try integer(historyLimitKey, in: section, within: InputSettings.historyLimitRange) {
            settings.historyLimit = limit
        }
        if let timeout = try integer(timeoutKey, in: section, within: InputSettings.generatorTimeoutRange) {
            settings.generatorTimeout = .milliseconds(timeout)
        }
        return settings
    }

    private static func integer(_ key: String, in section: TOMLSection, within range: ClosedRange<Int>)
        throws(ConfigError) -> Int?
    {
        guard let value = try section.number(key) else { return nil }
        guard value.rounded() == value, value >= Double(range.lowerBound), value <= Double(range.upperBound) else {
            throw section.error(at: key, "se esperaba un número entero entre \(range.lowerBound) y \(range.upperBound)")
        }
        return Int(value)
    }
}
