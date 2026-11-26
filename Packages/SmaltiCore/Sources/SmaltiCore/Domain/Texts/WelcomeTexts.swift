/// F7.7: the welcome card's words (spec «Primer arranque»).
public struct WelcomeTexts: Sendable, Equatable {
    public let title: String
    public let subtitle: TextTemplate
    public let inPalette: String
    public let shortcuts: [CommandID: String]
    public let rows: [WelcomeRow: String]
    public let install: String
    public let update: String
    public let installed: String
    public let installing: String
    public let claudeUnavailable: String
    public let neovimNotDetected: String
    public let hints: [WelcomeHint: String]
    public let spaceKey: String
    public let appearance: AppearanceCopy

    public static let spanish = WelcomeTexts(
        title: "Bienvenido a Smalti", subtitle: "Todo está en {palette}: escribe lo que quieres hacer.",
        inPalette: "en ⌘K",
        shortcuts: [
            .paletteOpen: "Paleta de comandos", .helpShow: "Ayuda y atajos", .observatoryToggle: "Observatorio",
            .harnessSearch: "Sesiones de agentes", .paneNew: "Dividir panel",
            .agentJump: "Saltar al agente que te espera",
            .workspaceNew: "Nuevo workspace",
        ],
        rows: [.claude: "Integración con Claude Code", .neovim: "Integración con Neovim (lazy.nvim)", .theme: "Tema"],
        install: "espacio: instalar", update: "espacio: actualizar", installed: "instalada", installing: "instalando…",
        claudeUnavailable: "no disponible: instala Claude Code",
        neovimNotDetected: "no detectada: ver la documentación",
        hints: [.choose: "elegir", .install: "instalar", .theme: "tema", .skip: "saltar", .start: "empezar"],
        spaceKey: "espacio", appearance: .spanish)

    public static let english = WelcomeTexts(
        title: "Welcome to Smalti", subtitle: "Everything is in {palette}: type what you want to do.",
        inPalette: "in ⌘K",
        shortcuts: [
            .paletteOpen: "Command palette", .helpShow: "Help and shortcuts", .observatoryToggle: "Observatory",
            .harnessSearch: "Agent sessions", .paneNew: "Split pane", .agentJump: "Jump to the waiting agent",
            .workspaceNew: "New workspace",
        ],
        rows: [.claude: "Claude Code integration", .neovim: "Neovim integration (lazy.nvim)", .theme: "Theme"],
        install: "space: install", update: "space: update", installed: "installed", installing: "installing…",
        claudeUnavailable: "unavailable: install Claude Code", neovimNotDetected: "not detected: see the documentation",
        hints: [.choose: "choose", .install: "install", .theme: "theme", .skip: "skip", .start: "start"],
        spaceKey: "space", appearance: .english)
}

/// The footer's keys, in order: ↑↓ elegir, espacio instalar, ←→ tema, esc saltar, ↩ empezar.
public enum WelcomeHint: CaseIterable, Hashable, Sendable {
    case choose, install, theme, skip, start
}
