/// Smalti's integrations with other tools, each installed and removed from ⌘K (F5.6 had only Claude's; F6 adds
/// claudecode.nvim). A new integration is a new case with its own commands and titles.
public enum IntegrationID: CaseIterable, Hashable, Sendable {
    case claudePlugin
    case claudecodeNvim

    public var installCommand: CommandID {
        switch self {
        case .claudePlugin: .claudeIntegrationInstall
        case .claudecodeNvim: .claudecodeNvimInstall
        }
    }

    public var uninstallCommand: CommandID {
        switch self {
        case .claudePlugin: .claudeIntegrationUninstall
        case .claudecodeNvim: .claudecodeNvimUninstall
        }
    }

    public var installTitle: String {
        switch self {
        case .claudePlugin: "Instalar integración con Claude Code"
        case .claudecodeNvim: "Instalar claudecode.nvim en Neovim"
        }
    }

    public var uninstallTitle: String {
        switch self {
        case .claudePlugin: "Desinstalar integración con Claude Code"
        case .claudecodeNvim: "Desinstalar claudecode.nvim"
        }
    }

    /// F7.5: reinstalls an integration older than this Smalti's.
    public var updateTitle: String {
        switch self {
        case .claudePlugin: "Actualizar integración con Claude Code"
        case .claudecodeNvim: "Actualizar claudecode.nvim"
        }
    }

    /// The status bar line after a successful install.
    public var installedText: String {
        switch self {
        case .claudePlugin: "Integración con Claude Code instalada"
        case .claudecodeNvim: "claudecode.nvim instalado: se activa al abrir Neovim"
        }
    }

    public var uninstalledText: String {
        switch self {
        case .claudePlugin: "Integración con Claude Code desinstalada"
        case .claudecodeNvim: "claudecode.nvim desinstalado"
        }
    }

    /// Only the action that applies to the state; none while it is unknown (spec F5.6).
    func commandID(for state: IntegrationState) -> (id: CommandID, title: String)? {
        switch state {
        case .notInstalled: (installCommand, installTitle)
        case .installed: (uninstallCommand, uninstallTitle)
        case .outdated: (installCommand, updateTitle)
        case .unknown: nil
        }
    }
}
