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
        static let observatory = "observatory"
        static let input = "input"
        static let window = "window"
        static let preview = "preview"
        static let extras = "extras"
    }

    static let prompt = "prompt"

    static func parse(_ text: String, file: String) throws(ConfigError) -> SmaltiConfig {
        let root = try TOMLSection.root(of: TOMLSource(text: text, file: file))
        try root.rejectUnknownKeys(allowed: [
            Table.appearance, Table.tiling, Table.shell, Table.keys, Table.observatory, Table.input, Table.window,
            prompt, Table.preview, Table.extras,
        ])
        var config = SmaltiConfig.defaults
        try readLook(root, into: &config, scope: .config)
        if let section = try root.section(Table.tiling) {
            config.defaultLayout = try TilingReader.read(section) ?? config.defaultLayout
        }
        if let section = try root.section(Table.shell) {
            config.shell = try ShellReader.read(section) ?? config.shell
        }
        if let section = try root.section(Table.keys) {
            config.keys = try TOMLKeysReader.read(section, over: config.keys)
        }
        if let section = try root.section(Table.observatory) {
            config.observatory = try ObservatoryReader.read(section)
        }
        if let section = try root.section(Table.input) {
            config.input = try InputReader.read(section)
        }
        if let section = try root.section(Table.preview) {
            config.preview = try PreviewReader.read(section)
        }
        if let section = try root.section(Table.extras) {
            config.extras = try ExtrasReader.read(section)
        }
        return config
    }

    /// `theme.toml` (spec F5): only `[appearance]`, `[window] buttons` and `[prompt]`, read over `base` key by key.
    static func parseTheme(_ text: String, file: String, over base: SmaltiConfig) throws(ConfigError) -> SmaltiConfig {
        let root = try TOMLSection.root(of: TOMLSource(text: text, file: file))
        try root.rejectUnknownKeys(allowed: [Table.appearance, Table.window, prompt])
        var config = base
        try readLook(root, into: &config, scope: .theme)
        return config
    }

    /// The look tables both files share.
    private static func readLook(_ root: TOMLSection, into config: inout SmaltiConfig, scope: LookScope)
        throws(ConfigError)
    {
        if let section = try root.section(Table.appearance) {
            config.appearance = try AppearanceReader.read(section, over: config.appearance)
        }
        if let section = try root.section(Table.window) {
            config.window = try WindowReader.read(section, over: config.window, scope: scope)
        }
        if let section = try root.section(prompt) {
            config.prompt = try PromptReader.read(section, over: config.prompt)
        }
    }

    /// Dotted keys written in the look tables (`appearance.blur`, `appearance.ansi.bosque.1`…), for the warning on
    /// keys set in both files.
    static func lookKeys(_ text: String, file: String) throws(ConfigError) -> Set<String> {
        let root = try TOMLSection.root(of: TOMLSource(text: text, file: file))
        var keys: Set<String> = []
        for table in [Table.appearance, Table.window, prompt] {
            guard let section = try root.section(table) else { continue }
            try collect(section, into: &keys)
        }
        return keys
    }

    private static func collect(_ section: TOMLSection, into keys: inout Set<String>) throws(ConfigError) {
        for key in section.keysInFileOrder {
            // A nested table (`ansi.bosque`) is walked; a scalar key fails `section` and is recorded.
            if let nested = try? section.section(key) {
                try collect(nested, into: &keys)
            } else {
                keys.insert("\(section.name).\(key)")
            }
        }
    }
}

/// Which file a look table comes from: `confirm_close` belongs to `config.toml` only (the UI never writes it).
enum LookScope {
    case config
    case theme
}

/// Reads a word of `T`'s raw values, with the choices in the error ("se esperaba hidden, hover o visible").
enum Choice {
    static func read<T: RawRepresentable & CaseIterable>(
        _ key: String, in section: TOMLSection, as type: T.Type, prefix: String = ""
    ) throws(ConfigError) -> T? where T.RawValue == String {
        guard let text = try section.text(key, reason: reason(T.self, prefix: prefix)) else { return nil }
        guard let value = T(rawValue: text) else { throw section.error(at: key, reason(T.self, prefix: prefix)) }
        return value
    }

    static func reason<T: RawRepresentable & CaseIterable>(_ type: T.Type, prefix: String = "") -> String
    where T.RawValue == String {
        let words = T.allCases.map(\.rawValue)
        let list =
            words.count > 1 ? words.dropLast().joined(separator: ", ") + " o " + (words.last ?? "") : words.joined()
        return prefix + "se esperaba " + list
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

    private static let glassOpacity = Bounds(AppearanceSettings.glassOpacityRange, "0,3 y 0,95")
    private static let blur = Bounds(AppearanceSettings.blurRange, "0 y 48")
    private static let fontSize = Bounds(AppearanceSettings.fontSizeRange, "6 y 72")
    private static let gap = Bounds(AppearanceSettings.gapRange, "0 y 32")
    private static let radius = Bounds(AppearanceSettings.radiusRange, "0 y 32")
    private static let accentReason = "se esperaba un color #rrggbb"
    private static let fontFamilyKey = "font_family"
    private static let fontFamilyReason =
        "se esperaba un nombre de 1 a \(AppearanceSettings.maximumFontFamilyLength) caracteres sin comillas, "
        + "\\ ni caracteres de control"

    static func read(_ section: TOMLSection, over defaults: AppearanceSettings) throws(ConfigError)
        -> AppearanceSettings
    {
        try section.rejectUnknownKeys(allowed: [
            "accent", "glass_opacity", "blur", "font_family", "font_size", "gap", "radius", "theme",
            "protect_legibility", "ansi",
        ])
        var appearance = defaults
        appearance.theme =
            try Choice.read("theme", in: section, as: ThemeID.self, prefix: "tema desconocido; ") ?? appearance.theme
        appearance.protectLegibility = try section.flag("protect_legibility") ?? appearance.protectLegibility
        if let ansi = try section.section("ansi") {
            // Per index across files (block 3 review, M7): theme.toml's colors over config.toml's, one by one.
            appearance.ansiOverrides.merge(try ANSIReader.read(ansi)) { earlier, written in earlier.merging(written) }
        }
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

/// `[window]`: `confirm_close` (F4.5, `config.toml` only) and `buttons` (F5).
private enum WindowReader {
    private static let confirmCloseKey = "confirm_close"
    private static let buttonsKey = "buttons"

    static func read(_ section: TOMLSection, over base: WindowSettings, scope: LookScope) throws(ConfigError)
        -> WindowSettings
    {
        let allowed: Set<String> = scope == .config ? [confirmCloseKey, buttonsKey] : [buttonsKey]
        try section.rejectUnknownKeys(allowed: allowed)
        var settings = base
        settings.confirmClose = try section.flag(confirmCloseKey) ?? settings.confirmClose
        settings.buttons = try Choice.read(buttonsKey, in: section, as: WindowButtons.self) ?? settings.buttons
        return settings
    }
}
