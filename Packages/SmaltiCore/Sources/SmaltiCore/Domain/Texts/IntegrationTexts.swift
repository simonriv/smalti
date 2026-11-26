/// F7.7: the words of Smalti's integrations in ⌘K, the help and the status bar.
public struct IntegrationTexts: Sendable {
    public let install: [IntegrationID: String]
    public let uninstall: [IntegrationID: String]
    /// F7.5: reinstalls an integration older than this Smalti's.
    public let update: [IntegrationID: String]
    /// The status bar line after a successful install or uninstall.
    public let installed: [IntegrationID: String]
    public let uninstalled: [IntegrationID: String]
    public let harnessMissing: TextTemplate
    public let commandFailed: TextTemplate

    public static let spanish = IntegrationTexts(
        install: [
            .claudePlugin: "Instalar integración con Claude Code",
            .claudecodeNvim: "Instalar claudecode.nvim en Neovim",
        ],
        uninstall: [
            .claudePlugin: "Desinstalar integración con Claude Code", .claudecodeNvim: "Desinstalar claudecode.nvim",
        ],
        update: [
            .claudePlugin: "Actualizar integración con Claude Code", .claudecodeNvim: "Actualizar claudecode.nvim",
        ],
        installed: [
            .claudePlugin: "Integración con Claude Code instalada",
            .claudecodeNvim: "claudecode.nvim instalado: se activa al abrir Neovim",
        ],
        uninstalled: [
            .claudePlugin: "Integración con Claude Code desinstalada", .claudecodeNvim: "claudecode.nvim desinstalado",
        ],
        harnessMissing: "No se encontró `{binary}` en el PATH del shell de inicio",
        commandFailed: "Falló `{command}`: {output}")

    public static let english = IntegrationTexts(
        install: [
            .claudePlugin: "Install Claude Code Integration", .claudecodeNvim: "Install claudecode.nvim in Neovim",
        ],
        uninstall: [.claudePlugin: "Uninstall Claude Code Integration", .claudecodeNvim: "Uninstall claudecode.nvim"],
        update: [.claudePlugin: "Update Claude Code Integration", .claudecodeNvim: "Update claudecode.nvim"],
        installed: [
            .claudePlugin: "Claude Code integration installed",
            .claudecodeNvim: "claudecode.nvim installed: it loads the next time Neovim starts",
        ],
        uninstalled: [
            .claudePlugin: "Claude Code integration uninstalled", .claudecodeNvim: "claudecode.nvim uninstalled",
        ],
        harnessMissing: "`{binary}` was not found in the login shell’s PATH",
        commandFailed: "`{command}` failed: {output}")
}
