/// Identifies something the user can do. The raw values are what users write in `config.toml`.
public struct CommandID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let paletteOpen = CommandID(rawValue: "palette.open")
    public static let layoutDwindle = CommandID(rawValue: "layout.dwindle")
    public static let layoutColumns = CommandID(rawValue: "layout.columns")
    public static let layoutMaster = CommandID(rawValue: "layout.master")
    public static let panesEqualize = CommandID(rawValue: "panes.equalize")
    public static let paneNew = CommandID(rawValue: "pane.new")
    public static let paneClose = CommandID(rawValue: "pane.close")
    public static let workspaceNew = CommandID(rawValue: "workspace.new")
    public static let workspaceRename = CommandID(rawValue: "workspace.rename")
    public static let workspaceClose = CommandID(rawValue: "workspace.close")
    public static let configReload = CommandID(rawValue: "config.reload")
    public static let agentJump = CommandID(rawValue: "agent.jump")
    public static let claudeIntegrationInstall = CommandID(rawValue: "claude.integration.install")
    public static let claudeIntegrationUninstall = CommandID(rawValue: "claude.integration.uninstall")
    public static let observatoryToggle = CommandID(rawValue: "observatory.toggle")
    /// Cycles the observatory's period; acts only while the observatory is open, the terminal gets the key otherwise.
    public static let observatoryPeriod = CommandID(rawValue: "observatory.period")
    /// F4: opens the ⌃R history palette for the focused pane (⌃R itself is zsh's key there, not Smalti's).
    public static let historySearch = CommandID(rawValue: "history.search")

    // F4.5: windows, help, feedback, the app and the terminal's basic commands.
    public static let windowNew = CommandID(rawValue: "window.new")
    public static let windowClose = CommandID(rawValue: "window.close")
    public static let windowFullscreen = CommandID(rawValue: "window.fullscreen")
    public static let windowMinimize = CommandID(rawValue: "window.minimize")
    public static let helpShow = CommandID(rawValue: "help.show")
    public static let feedbackReport = CommandID(rawValue: "feedback.report")
    public static let logsShow = CommandID(rawValue: "logs.show")
    public static let appAbout = CommandID(rawValue: "app.about")
    public static let configOpen = CommandID(rawValue: "config.open")
    public static let terminalCopy = CommandID(rawValue: "terminal.copy")
    public static let terminalPaste = CommandID(rawValue: "terminal.paste")
    public static let terminalSelectAll = CommandID(rawValue: "terminal.selectAll")
    public static let terminalClear = CommandID(rawValue: "terminal.clear")
    public static let searchOpen = CommandID(rawValue: "search.open")
    public static let searchNext = CommandID(rawValue: "search.next")
    public static let searchPrevious = CommandID(rawValue: "search.previous")
    public static let fontIncrease = CommandID(rawValue: "font.increase")
    public static let fontDecrease = CommandID(rawValue: "font.decrease")
    public static let fontReset = CommandID(rawValue: "font.reset")
    public static let scrollPageUp = CommandID(rawValue: "scroll.pageUp")
    public static let scrollPageDown = CommandID(rawValue: "scroll.pageDown")
    public static let scrollTop = CommandID(rawValue: "scroll.top")
    public static let scrollBottom = CommandID(rawValue: "scroll.bottom")
    public static let promptPrevious = CommandID(rawValue: "prompt.previous")
    public static let promptNext = CommandID(rawValue: "prompt.next")
    public static let secureInputToggle = CommandID(rawValue: "secureInput.toggle")

    // F5: appearance and prompt (spec F5, "Comandos y atajos nuevos").
    public static let appearanceOpen = CommandID(rawValue: "appearance.open")
    public static let promptStudio = CommandID(rawValue: "prompt.studio")
    public static let themeOpen = CommandID(rawValue: "theme.open")
    public static let themeNext = CommandID(rawValue: "theme.next")
    public static let ansiReset = CommandID(rawValue: "ansi.reset")
    public static let promptApply = CommandID(rawValue: "prompt.apply")
    public static let promptExport = CommandID(rawValue: "prompt.export")
    public static let legibilityToggle = CommandID(rawValue: "legibility.toggle")

    /// The F5 commands, in the order ⌘K, the help and the menu list them.
    static let appearance: [CommandID] = [
        appearanceOpen, promptStudio, themeOpen, themeNext, ansiReset, promptApply, promptExport, legibilityToggle,
    ]

    /// The F4.5 commands, in the order the help and the menus list them.
    static let basics: [CommandID] = [
        windowNew, windowClose, windowFullscreen, windowMinimize, helpShow, feedbackReport, logsShow, appAbout,
        configOpen, terminalCopy, terminalPaste, terminalSelectAll, terminalClear, searchOpen, searchNext,
        searchPrevious, fontIncrease, fontDecrease, fontReset, scrollPageUp, scrollPageDown, scrollTop, scrollBottom,
        promptPrevious, promptNext, secureInputToggle,
    ]

    /// Focus the nth pane, `number` in `NumberedShortcuts.range`.
    public static func paneFocus(_ number: Int) -> CommandID { CommandID(rawValue: "pane.focus.\(number)") }
    public static func paneFocus(_ direction: Direction) -> CommandID {
        CommandID(rawValue: "pane.focus.\(direction.name)")
    }
    public static func paneSwap(_ direction: Direction) -> CommandID {
        CommandID(rawValue: "pane.swap.\(direction.name)")
    }
    public static func paneResize(_ direction: Direction) -> CommandID {
        CommandID(rawValue: "pane.resize.\(direction.name)")
    }
    /// Select the layout with this id; matches the `layoutDwindle`, `layoutColumns` and `layoutMaster` members.
    public static func layout(_ id: LayoutID) -> CommandID { CommandID(rawValue: "layout.\(id.rawValue)") }
    /// Go to one workspace by identity. Not bindable: it is only offered by the command palette.
    public static func workspaceGo(_ id: WorkspaceID) -> CommandID {
        CommandID(rawValue: "workspace.go.\(id.rawValue.uuidString)")
    }
    /// Go to the nth workspace, `number` in `NumberedShortcuts.range`.
    public static func workspace(_ number: Int) -> CommandID { CommandID(rawValue: "workspace.\(number)") }

    private static let layoutSavePrefix = "layout.save:"
    private static let layoutRestorePrefix = "layout.restore:"

    public static func layoutSave(_ name: LayoutName) -> CommandID {
        CommandID(rawValue: layoutSavePrefix + name.rawValue)
    }

    public static func layoutRestore(_ name: LayoutName) -> CommandID {
        CommandID(rawValue: layoutRestorePrefix + name.rawValue)
    }

    /// The saved-layout action this command stands for, if any.
    public var namedLayout: NamedLayoutCommand? {
        if rawValue.hasPrefix(Self.layoutSavePrefix) {
            return (try? LayoutName(String(rawValue.dropFirst(Self.layoutSavePrefix.count)))).map { .save($0) }
        }
        if rawValue.hasPrefix(Self.layoutRestorePrefix) {
            return (try? LayoutName(String(rawValue.dropFirst(Self.layoutRestorePrefix.count)))).map { .restore($0) }
        }
        return nil
    }

    /// Every command the app ships, bound or not.
    public static let allStandard: [CommandID] =
        [
            paletteOpen, layoutDwindle, layoutColumns, layoutMaster, panesEqualize, paneNew, paneClose,
            workspaceNew, workspaceRename, workspaceClose, configReload, agentJump, observatoryToggle,
            observatoryPeriod, historySearch,
        ]
        + basics
        + appearance
        + NumberedShortcuts.range.map { paneFocus($0) } + NumberedShortcuts.range.map { workspace($0) }
        + Direction.allCases.flatMap { [paneFocus($0), paneSwap($0), paneResize($0)] }
}

extension Direction {
    /// The word used in command identifiers and key names.
    var name: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .up: "up"
        case .down: "down"
        }
    }
}

public enum NamedLayoutCommand: Equatable, Sendable {
    case save(LayoutName)
    case restore(LayoutName)
}
