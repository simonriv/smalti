import SmaltiCore

/// `[appearance.ansi.<tema>]`: the user's ANSI edits per theme, index 0–15 to `#rrggbb` (spec F5).
enum ANSIReader {
    private static let indexReason = "se esperaba un índice ANSI de 0 a 15"
    private static let colorReason = "se esperaba un color #rrggbb"

    static func read(_ section: TOMLSection) throws(ConfigError) -> [ThemeID: ANSIOverrides] {
        try section.rejectUnknownKeys(allowed: Set(ThemeID.allCases.map(\.rawValue)))
        var overrides: [ThemeID: ANSIOverrides] = [:]
        for theme in ThemeID.allCases {
            guard let table = try section.section(theme.rawValue) else { continue }
            overrides[theme] = try colors(in: table)
        }
        return overrides
    }

    private static func colors(in table: TOMLSection) throws(ConfigError) -> ANSIOverrides {
        var colors: [Int: RGBAColor] = [:]
        for key in table.keysInFileOrder {
            guard let index = Int(key), ANSIOverrides.range.contains(index) else {
                throw table.error(at: key, indexReason)
            }
            colors[index] = try color(key, in: table)
        }
        do {
            return try ANSIOverrides(colors)
        } catch {
            throw table.error(at: table.keysInFileOrder.first ?? "", indexReason)
        }
    }

    private static func color(_ key: String, in table: TOMLSection) throws(ConfigError) -> RGBAColor {
        guard let text = try table.text(key, reason: colorReason), text.wholeMatch(of: /#[0-9a-fA-F]{6}/) != nil
        else { throw table.error(at: key, colorReason) }
        do {
            return try RGBAColor(hex: text)
        } catch {
            throw table.error(at: key, colorReason)
        }
    }
}

/// `[prompt]` (spec F5): the prompt studio's settings, read over `base` key by key.
enum PromptReader {
    private static let modulesKey = "modules"

    static func read(_ section: TOMLSection, over base: PromptConfig) throws(ConfigError) -> PromptConfig {
        try section.rejectUnknownKeys(allowed: ["source", "style", "layout", modulesKey, "icons", "symbol"])
        var prompt = base
        prompt.source = try Choice.read("source", in: section, as: PromptSource.self) ?? prompt.source
        prompt.style = try Choice.read("style", in: section, as: PromptStyleID.self) ?? prompt.style
        prompt.layout = try Choice.read("layout", in: section, as: PromptLayout.self) ?? prompt.layout
        prompt.modules = try modules(in: section) ?? prompt.modules
        prompt.icons = try Choice.read("icons", in: section, as: PromptIcons.self) ?? prompt.icons
        prompt.symbol = try Choice.read("symbol", in: section, as: PromptSymbol.self) ?? prompt.symbol
        return prompt
    }

    private static func modules(in section: TOMLSection) throws(ConfigError) -> [PromptModuleID]? {
        guard let words = try section.texts(modulesKey) else { return nil }
        var modules: [PromptModuleID] = []
        for word in words {
            guard let module = PromptModuleID(rawValue: word) else {
                try section.skipUnknownValue(
                    word, at: modulesKey, else: section.error(at: modulesKey, "módulo desconocido: \(word)"))
                continue
            }
            guard !modules.contains(module) else { throw section.error(at: modulesKey, "módulo repetido: \(word)") }
            modules.append(module)
        }
        return modules
    }
}
