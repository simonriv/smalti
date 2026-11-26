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

    /// Only the action that applies to the state; none while it is unknown (spec F5.6).
    func command(for state: IntegrationState, texts: IntegrationTexts) -> (id: CommandID, title: String)? {
        switch state {
        case .notInstalled: (installCommand, texts.install[self] ?? "")
        case .installed: (uninstallCommand, texts.uninstall[self] ?? "")
        case .outdated: (installCommand, texts.update[self] ?? "")
        case .unknown: nil
        }
    }
}
