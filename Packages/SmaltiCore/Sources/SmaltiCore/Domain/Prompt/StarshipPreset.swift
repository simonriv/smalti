/// `starship.toml` as a model (spec F5, "Exportar como starship.toml"); `TOMLConfigAdapter` writes it as text.
public struct StarshipPreset: Equatable, Sendable {
    public let format: String
    public let tables: [StarshipTable]
    /// Lines written as `#` comments at the top: what cannot be exported.
    public let comments: [String]
    /// Top-level keys: no blank line before each prompt, as in Smalti.
    public let settings: [StarshipEntry] = [StarshipEntry(key: "add_newline", value: .boolean(false))]

    public func table(_ name: String) -> StarshipTable? {
        tables.first { $0.name == name }
    }

    public static func make(from config: PromptConfig, theme: AppliedTheme) -> StarshipPreset {
        StarshipBuilder(config: config, theme: theme.theme).preset()
    }
}

public struct StarshipTable: Equatable, Sendable {
    public let name: String
    public let entries: [StarshipEntry]

    public func value(_ key: String) -> StarshipValue? {
        entries.first { $0.key == key }?.value
    }
}

public struct StarshipEntry: Equatable, Sendable {
    public let key: String
    public let value: StarshipValue
}

public enum StarshipValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
}

/// Builds the preset; each module brings its own tables (`PromptModule.starshipTables`).
public struct StarshipBuilder {
    let config: PromptConfig
    let theme: Theme

    private static let agentsComment =
        "Agentes que esperan: solo existe dentro de Smalti; no tiene equivalente en Starship."

    func preset() -> StarshipPreset {
        let character = table(
            "character",
            [
                ("success_symbol", .string("[\(Self.literal(config.symbol.rawValue))](\(hex(.accent)))")),
                ("error_symbol", .string("[\(Self.literal(config.symbol.rawValue))](\(hex(.failed)))")),
            ])
        guard config.style != .symbolOnly else {
            return StarshipPreset(format: "$character", tables: [character], comments: [])
        }
        let modules = config.modules.flatMap(tables(for:))
        let lineBreak = config.layout == .twoLines ? "$line_break" : ""
        let format = modules.map { "$" + $0.name }.joined() + lineBreak + "$character"
        let comments = config.modules.contains(.agents) ? [Self.agentsComment] : []
        return StarshipPreset(format: format, tables: modules + [character], comments: comments)
    }

    private func tables(for id: PromptModuleID) -> [StarshipTable] {
        PromptModules.module(for: id).starshipTables(using: self)
    }

    /// `symbol` is Starship's own variable; `icon` is written into the format.
    /// Text inside a Starship format string: `$`, brackets, parentheses and `\\` are its syntax (block 2 review, I4).
    static func literal(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if "\\$[]()".contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    func module(
        _ name: String, _ body: String, _ role: SegmentColor, symbol: PromptIcon? = nil, icon: PromptIcon? = nil,
        extra: [(String, StarshipValue)] = []
    ) -> StarshipTable {
        let prefix = icon.flatMap(nerd).map { $0 + " " } ?? ""
        var entries: [(String, StarshipValue)] = [
            ("style", .string(style(role))), ("format", .string(wrap(prefix + body, role))),
        ]
        if let symbol { entries.insert(("symbol", .string(nerd(symbol).map { $0 + " " } ?? "")), at: 0) }
        return table(name, entries + extra)
    }

    /// Only Nerd Font glyphs exist outside Smalti; thin icons and "Sin iconos" export none.
    private func nerd(_ icon: PromptIcon) -> String? {
        config.icons == .nerd ? PromptIcons.nerd.character(for: icon).map(String.init) : nil
    }

    func wrap(_ body: String, _ role: SegmentColor, optional: Bool = false) -> String {
        let padded = config.style == .pills ? " \(body) " : body
        let segment = "[\(padded)]($style) "
        return optional ? "(\(segment))" : segment
    }

    func style(_ role: SegmentColor) -> String {
        guard config.style == .pills else { return hex(role) }
        let background = PillsStyle.background(of: theme.color(for: role), over: theme.panel.background)
        return "fg:\(hex(role)) bg:\(background.hexString)"
    }

    private func hex(_ role: SegmentColor) -> String {
        theme.color(for: role).hexString
    }

    func table(_ name: String, _ entries: [(String, StarshipValue)]) -> StarshipTable {
        StarshipTable(name: name, entries: entries.map { StarshipEntry(key: $0.0, value: $0.1) })
    }
}
