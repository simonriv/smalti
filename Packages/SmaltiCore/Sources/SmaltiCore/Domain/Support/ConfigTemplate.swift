/// The `config.toml` that ⌘, creates when there is none: every table and key, commented, with its default value,
/// so the user uncomments what they want to change.
public enum ConfigTemplate {
    public static func text(defaults: SmaltiConfig) -> String {
        let appearance = defaults.appearance
        let input = defaults.input
        return """
            # Configuración de Smalti. Quita el # de una línea para cambiar su valor; lo que no escribas conserva \
            el valor por defecto.
            # Después de guardar: ⌘K → "Recargar configuración".

            [appearance]
            # accent = "\(appearance.accent.hexString)"
            # glass_opacity = \(number(appearance.glassOpacity))
            # blur = \(number(appearance.blur))
            # font_family = "\(appearance.fontFamily)"
            # font_size = \(number(appearance.fontSize))
            # gap = \(number(appearance.gap))
            # radius = \(number(appearance.radius))

            [tiling]
            # Layouts: dwindle, columns, master.
            # default_layout = "\(defaults.defaultLayout.rawValue)"

            [shell]
            # "login" abre tu shell de inicio de sesión; también vale una orden, por ejemplo "/bin/zsh".
            # command = "\(shell(defaults.shell))"

            [input]
            # enabled = \(input.isEnabled)
            # predictions = \(input.hasPredictions)
            # completions = \(input.hasCompletions)
            # history_limit = \(input.historyLimit)
            # generator_timeout_ms = \(milliseconds(input.generatorTimeout))

            [window]
            # Preguntar antes de cerrar un panel, un workspace o una ventana, o de salir, con procesos en marcha.
            # confirm_close = \(defaults.window.confirmClose)

            [keys]
            # Un atajo por línea, del atajo al comando, por ejemplo cmd+t para pane.new (ids en la ayuda, ⌘?).
            # Los atajos que escribas para un comando reemplazan los suyos por defecto; dos líneas para el mismo
            # comando le dan dos atajos. "none" suelta un atajo.

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
