import SmaltiCore

/// Turns the text of `config.toml` into a `SmaltiConfig`. Tables and keys that are not written keep their default;
/// unknown ones are errors.
///
/// `[keys]` maps a chord to a command id: `"cmd+k" = "palette.open"`, or `"none"` to unbind the chord. A chord is
/// modifiers (`cmd`, `ctrl`, `opt`, `shift`) and one key joined by `+`. The `+` key itself is written `plus`
/// (`"cmd+plus"`), because `"cmd++"` is not supported.
enum TOMLConfigParser {
    private enum Table {
        static let appearance = "appearance"
        static let tiling = "tiling"
        static let shell = "shell"
        static let keys = "keys"
    }

    static func parse(_ text: String, file: String) throws(ConfigError) -> SmaltiConfig {
        let root = try TOMLSection.root(of: TOMLSource(text: text, file: file))
        try root.rejectUnknownKeys(allowed: [Table.appearance, Table.tiling, Table.shell, Table.keys])
        var config = SmaltiConfig.defaults
        if let section = try root.section(Table.appearance) {
            config.appearance = try AppearanceReader.read(section, over: config.appearance)
        }
        if let section = try root.section(Table.tiling) {
            config.defaultLayout = try TilingReader.read(section) ?? config.defaultLayout
        }
        if let section = try root.section(Table.shell) {
            config.shell = try ShellReader.read(section) ?? config.shell
        }
        if let section = try root.section(Table.keys) {
            config.keys = try TOMLKeysReader.read(section, over: config.keys)
        }
        return config
    }
}

/// `[appearance]`. Glass and blur ranges come from the sliders in `docs/design/Apariencia.dc.html`; font size, gap
/// and radius have no board range, so theirs are sanity bounds that can be widened. Non-finite values never pass.
private enum AppearanceReader {
    private struct Bounds {
        let range: ClosedRange<Double>
        let reason: String

        init(_ range: ClosedRange<Double>, _ text: String) {
            self.range = range
            self.reason = "se esperaba un número entre \(text)"
        }
    }

    private static let glassOpacity = Bounds(0.3...0.95, "0,3 y 0,95")
    private static let blur = Bounds(0...48, "0 y 48")
    private static let fontSize = Bounds(6...72, "6 y 72")
    private static let gap = Bounds(0...32, "0 y 32")
    private static let radius = Bounds(0...32, "0 y 32")
    private static let accentReason = "se esperaba un color #rrggbb"
    private static let fontFamilyKey = "font_family"
    private static let fontFamilyReason =
        "se esperaba un nombre de 1 a \(AppearanceSettings.maximumFontFamilyLength) caracteres sin comillas, "
        + "\\ ni caracteres de control"

    static func read(_ section: TOMLSection, over defaults: AppearanceSettings) throws(ConfigError)
        -> AppearanceSettings
    {
        try section.rejectUnknownKeys(allowed: [
            "accent", "glass_opacity", "blur", "font_family", "font_size", "gap", "radius",
        ])
        var appearance = defaults
        appearance.accent = try accent(in: section) ?? appearance.accent
        appearance.glassOpacity = try number("glass_opacity", in: section, glassOpacity) ?? appearance.glassOpacity
        appearance.blur = try number("blur", in: section, blur) ?? appearance.blur
        appearance.fontFamily = try fontFamily(in: section) ?? appearance.fontFamily
        appearance.fontSize = try number("font_size", in: section, fontSize) ?? appearance.fontSize
        appearance.gap = try number("gap", in: section, gap) ?? appearance.gap
        appearance.radius = try number("radius", in: section, radius) ?? appearance.radius
        return appearance
    }

    private static func accent(in section: TOMLSection) throws(ConfigError) -> RGBAColor? {
        guard let text = try section.text("accent", reason: accentReason) else { return nil }
        guard text.wholeMatch(of: /#[0-9a-fA-F]{6}/) != nil else { throw section.error(at: "accent", accentReason) }
        do {
            return try RGBAColor(hex: text)
        } catch {
            throw section.error(at: "accent", accentReason)
        }
    }

    /// The name ends up inside a quoted line of the generated libghostty config, so anything that could close the
    /// quote or start a new line is refused here, at the boundary.
    private static func fontFamily(in section: TOMLSection) throws(ConfigError) -> String? {
        guard let text = try section.text(fontFamilyKey) else { return nil }
        guard AppearanceSettings.isValidFontFamily(text) else {
            throw section.error(at: fontFamilyKey, fontFamilyReason)
        }
        return text
    }

    private static func number(_ key: String, in section: TOMLSection, _ bounds: Bounds) throws(ConfigError)
        -> Double?
    {
        guard let value = try section.number(key) else { return nil }
        guard value.isFinite, bounds.range.contains(value) else { throw section.error(at: key, bounds.reason) }
        return value
    }
}

/// `[tiling]`: `default_layout` must name a layout of `LayoutCatalog.standard`.
private enum TilingReader {
    private static let key = "default_layout"

    static func read(_ section: TOMLSection) throws(ConfigError) -> LayoutID? {
        try section.rejectUnknownKeys(allowed: [key])
        guard let text = try section.text(key) else { return nil }
        let id = LayoutID(rawValue: text)
        guard LayoutCatalog.standard.strategy(for: id) != nil else {
            throw section.error(at: key, "layout desconocido; se esperaba \(knownLayouts)")
        }
        return id
    }

    /// `dwindle, columns o master`.
    private static var knownLayouts: String {
        let ids = LayoutCatalog.standard.all.map(\.id.rawValue)
        guard let last = ids.last, ids.count > 1 else { return ids.joined() }
        return ids.dropLast().joined(separator: ", ") + " o " + last
    }
}

/// `[shell]`: `command = "login"` is the user's login shell; any other non-blank text is run as is.
private enum ShellReader {
    private static let key = "command"
    private static let loginKeyword = "login"
    private static let reason = "se esperaba un comando o \"login\""

    static func read(_ section: TOMLSection) throws(ConfigError) -> TerminalCommand? {
        try section.rejectUnknownKeys(allowed: [key])
        guard let text = try section.text(key, reason: reason) else { return nil }
        if text == loginKeyword { return .loginShell }
        guard text.contains(where: { !$0.isWhitespace }) else { throw section.error(at: key, reason) }
        return .custom(text)
    }
}
