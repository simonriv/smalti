import SmaltiCore

/// The text of `theme.toml` (spec F5): every key the UI owns, in the spec's order, with the choices as comments.
enum TOMLWriter {
    /// `texts` words the comments, in the interface's language when the file is written.
    static func text(_ document: AppearanceDocument, texts: ConfigTexts) -> String {
        let header = "# " + texts.themeFileHeader
        return
            ([header, "", "\(TOMLConfigParser.versionKey) = \(TOMLConfigParser.supportedVersion)", ""]
            + appearance(document.appearance, texts: texts) + ansi(document.appearance.ansiOverrides, texts: texts)
            + window(document.buttons) + prompt(document.prompt)).joined(separator: "\n") + "\n"
    }

    private static func appearance(_ appearance: AppearanceSettings, texts: ConfigTexts) -> [String] {
        var lines = [
            "[appearance]",
            line("theme", string(appearance.theme.rawValue), choices(ThemeID.self)),
        ]
        if let accent = appearance.accent {
            lines.append(line("accent", string(accent.hexString), texts.accentComment))
        }
        lines += [
            line("glass_opacity", number(appearance.glassOpacity), "0.30–0.95"),
            line("blur", number(appearance.blur), "0–48"),
            line("protect_legibility", String(appearance.protectLegibility)),
            line("font_family", string(appearance.fontFamily)),
            line("font_size", number(appearance.fontSize)),
            line("gap", number(appearance.gap)),
            line("radius", number(appearance.radius)),
            "",
        ]
        return lines
    }

    private static func ansi(_ overrides: [ThemeID: ANSIOverrides], texts: ConfigTexts) -> [String] {
        ThemeID.allCases.compactMap { theme -> [String]? in
            guard let colors = overrides[theme]?.colors, !colors.isEmpty else { return nil }
            let header =
                "[appearance.ansi.\(theme.rawValue)]"
                + (theme == .obsidiana ? "  # " + texts.ansiComment : "")
            return [header] + colors.keys.sorted().map { "\($0) = \(string(colors[$0]?.hexString ?? ""))" } + [""]
        }.flatMap { $0 }
    }

    private static func window(_ buttons: WindowButtons) -> [String] {
        ["[window]", line("buttons", string(buttons.rawValue), choices(WindowButtons.self)), ""]
    }

    private static func prompt(_ prompt: PromptConfig) -> [String] {
        [
            "[prompt]",
            line("source", string(prompt.source.rawValue), choices(PromptSource.self)),
            line("style", string(prompt.style.rawValue), choices(PromptStyleID.self)),
            line("layout", string(prompt.layout.rawValue), choices(PromptLayout.self)),
            "modules = [" + prompt.modules.map { string($0.rawValue) }.joined(separator: ", ") + "]",
            line("icons", string(prompt.icons.rawValue), choices(PromptIcons.self)),
            line("symbol", string(prompt.symbol.rawValue), choices(PromptSymbol.self)),
        ]
    }

    private static func line(_ key: String, _ value: String, _ comment: String? = nil) -> String {
        "\(key) = \(value)" + (comment.map { "  # \($0)" } ?? "")
    }

    private static func choices<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> String
    where T.RawValue == String {
        T.allCases.map(\.rawValue).joined(separator: " | ")
    }

    /// Integers without a decimal point; anything else in Swift's shortest form, which reads back exactly.
    static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    /// A TOML basic string.
    static func string(_ text: String) -> String {
        "\"" + text.unicodeScalars.map(escape).joined() + "\""
    }

    private static func escape(_ scalar: Unicode.Scalar) -> String {
        switch scalar {
        case "\"": return "\\\""
        case "\\": return "\\\\"
        case "\n": return "\\n"
        case "\t": return "\\t"
        default:
            guard scalar.properties.generalCategory == .control else { return String(scalar) }
            let hex = String(scalar.value, radix: 16, uppercase: true)
            return "\\u" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
        }
    }
}
