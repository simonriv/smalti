/// The welcome card's rows that can be chosen, top to bottom.
public enum WelcomeRow: CaseIterable, Hashable, Sendable {
    case claude, neovim, theme
}

/// What closing the card does: the theme to write (nil when it did not change) and whether to mark it seen.
public struct WelcomeOutcome: Equatable, Sendable {
    public let theme: ThemeID?
    public let marksDone: Bool

    public init(theme: ThemeID?, marksDone: Bool) {
        self.theme = theme
        self.marksDone = marksDone
    }
}

/// The welcome card's keyboard state (spec F7.7): ↑↓ choose a row, space installs, ←→ cycles the theme live,
/// ↩ keeps it and esc goes back to the theme it had.
public struct WelcomeState: Equatable, Sendable {
    public private(set) var selected = WelcomeRow.claude
    public var claude: IntegrationState
    public var neovim: IntegrationState
    public private(set) var theme: ThemeID
    public let originalTheme: ThemeID

    public init(claude: IntegrationState, neovim: IntegrationState, theme: ThemeID) {
        self.claude = claude
        self.neovim = neovim
        self.theme = theme
        originalTheme = theme
    }

    /// Stops at the first and last rows.
    public mutating func move(_ step: Int) {
        let rows = WelcomeRow.allCases
        let index = rows.firstIndex(of: selected) ?? 0
        selected = rows[min(max(index + step, 0), rows.count - 1)]
    }

    /// Wraps around the themes, in the Appearance panel's order.
    public mutating func cycleTheme(_ step: Int) {
        let themes = ThemeID.allCases
        let index = themes.firstIndex(of: theme) ?? 0
        theme = themes[((index + step) % themes.count + themes.count) % themes.count]
    }

    /// An integration row whose state lets space install or update it.
    public func canInstall(_ row: WelcomeRow) -> Bool {
        guard let state = integration(row) else { return false }
        return state == .notInstalled || state == .outdated
    }

    public func integration(_ row: WelcomeRow) -> IntegrationState? {
        switch row {
        case .claude: claude
        case .neovim: neovim
        case .theme: nil
        }
    }

    public func finish() -> WelcomeOutcome {
        WelcomeOutcome(theme: theme == originalTheme ? nil : theme, marksDone: true)
    }

    public func skip() -> WelcomeOutcome {
        WelcomeOutcome(theme: theme == originalTheme ? nil : originalTheme, marksDone: true)
    }

    /// The text right of a row.
    public func status(of row: WelcomeRow, texts: WelcomeTexts) -> String {
        switch row {
        case .theme: "‹ \(theme.displayName(texts.appearance)) ›"
        case .claude: integrationStatus(claude, unknown: texts.claudeUnavailable, texts: texts)
        case .neovim: integrationStatus(neovim, unknown: texts.neovimNotDetected, texts: texts)
        }
    }

    private func integrationStatus(_ state: IntegrationState, unknown: String, texts: WelcomeTexts) -> String {
        switch state {
        case .notInstalled: texts.install
        case .outdated: texts.update
        case .installed: texts.installed
        case .unknown: unknown
        }
    }
}
