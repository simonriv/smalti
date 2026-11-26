/// The `config.toml` that ⌘, creates when there is none: every table and key, commented, with its default value,
/// so the user uncomments what they want to change.
public enum ConfigTemplate {
    public static func text(defaults: SmaltiConfig, texts: ConfigTemplateTexts) -> String {
        let appearance = defaults.appearance
        let input = defaults.input
        let comment = { (lines: [String]) in lines.map { "# " + $0 }.joined(separator: "\n") }
        return """
            \(comment(texts.header))
            # \(texts.afterSave)

            # \(texts.format)
            version = 1

            [appearance]
            # accent = "\((appearance.accent ?? ThemeCatalog.theme(appearance.theme).accent).hexString)"
            # glass_opacity = \(number(appearance.glassOpacity))
            # blur = \(number(appearance.blur))
            # font_family = "\(escaped(appearance.fontFamily))"
            # font_size = \(number(appearance.fontSize))
            # gap = \(number(appearance.gap))
            # radius = \(number(appearance.radius))

            [tiling]
            # \(texts.layouts)
            # default_layout = "\(defaults.defaultLayout.rawValue)"

            [shell]
            # \(texts.shell)
            # command = "\(escaped(shell(defaults.shell)))"

            [input]
            # enabled = \(input.isEnabled)
            # predictions = \(input.hasPredictions)
            # completions = \(input.hasCompletions)
            # history_limit = \(input.historyLimit)
            # generator_timeout_ms = \(milliseconds(input.generatorTimeout))

            [keyboard]
            # \(texts.keyboard)
            # option_as_meta = "\(defaults.optionAsMeta.rawValue)"

            [window]
            # \(texts.confirmClose)
            # confirm_close = \(defaults.window.confirmClose)

            [preview]
            # \(texts.preview)
            # hover = \(defaults.preview.hover)

            [observatory]
            \(comment(texts.observatory))
            # [observatory.models."\(texts.exampleModel)"]
            #   input = 3
            #   output = 15
            #   cache_read = 0.3
            #   cache_write_5m = 3.75
            #   cache_write_1h = 6
            #   context = 200000

            [keys]
            # \(texts.keys[0])
            # "cmd+t" = "pane.new"
            \(comment(Array(texts.keys.dropFirst())))

            """
    }

    /// The template with every value line ("# key = value") uncommented; prose stays commented.
    public static func uncommented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            isCommentedValue(line) ? String(line.dropFirst(2)) : String(line)
        }.joined(separator: "\n")
    }

    private static func isCommentedValue(_ line: Substring) -> Bool {
        guard line.hasPrefix("# "), let equals = line.range(of: " = ") else { return false }
        let key = line[line.index(line.startIndex, offsetBy: 2)..<equals.lowerBound]
        return !key.isEmpty && key.allSatisfy { $0.isLowercase || $0 == "_" }
    }

    private static func milliseconds(_ duration: Duration) -> Int64 {
        duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000
    }

    /// A TOML basic string body: `\` and `"` escaped.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func shell(_ command: TerminalCommand) -> String {
        switch command {
        case .loginShell: "login"
        case .custom(let text): text
        }
    }
}
