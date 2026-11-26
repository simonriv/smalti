import Foundation

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
    /// F6: claudecode.nvim in the user's lazy.nvim config.
    public static let claudecodeNvimInstall = CommandID(rawValue: "claudecodeNvim.install")
    public static let claudecodeNvimUninstall = CommandID(rawValue: "claudecodeNvim.uninstall")
    public static let observatoryToggle = CommandID(rawValue: "observatory.toggle")
    /// F6: the session search card, Neovim beside the agent and at the last edited file, the observatory's filter.
    public static let harnessSearch = CommandID(rawValue: "harness.search")
    public static let editorOpenBeside = CommandID(rawValue: "editor.openBeside")
    public static let editorOpenLastEdited = CommandID(rawValue: "editor.openLastEdited")
    /// Cycles the observatory's harness filter; like the period, it acts only while the observatory is open.
    public static let observatoryFilter = CommandID(rawValue: "observatory.filter")
    /// F7: imports a shared layout file as a saved layout.
    public static let layoutImport = CommandID(rawValue: "layout.import")
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
    // F7.6: updates, documentation and support.
    public static let updatesCheck = CommandID(rawValue: "updates.check")
    public static let updatesAutomatic = CommandID(rawValue: "updates.automatic")
    public static let helpDocs = CommandID(rawValue: "help.docs")
    public static let appSupport = CommandID(rawValue: "app.support")
    // F7.7: the welcome card and the privacy policy.
    public static let helpWelcome = CommandID(rawValue: "help.welcome")
    public static let helpPrivacy = CommandID(rawValue: "help.privacy")
    // F8: the processes and ports views. The last four act on the open view and pass to the terminal otherwise.
    public static let processesToggle = CommandID(rawValue: "processes.toggle")
    public static let portsToggle = CommandID(rawValue: "ports.toggle")
    public static let processesStop = CommandID(rawValue: "processes.stop")
    public static let processesLowerPriority = CommandID(rawValue: "processes.lowerPriority")
    public static let processesTree = CommandID(rawValue: "processes.tree")
    public static let processesSort = CommandID(rawValue: "processes.sort")
    /// F8: what acts only while the processes view is open.
    public static let processesContextual: Set<CommandID> = [
        processesStop, processesLowerPriority, processesTree, processesSort,
    ]
    public static let processes: [CommandID] = [
        processesToggle, portsToggle, processesStop, processesLowerPriority, processesTree, processesSort,
    ]
    // F9: the timeline. ⇧⌘C copies the call only inside it; ⌘F and ⌘C reach it through the terminal's own keys.
    public static let timelineToggle = CommandID(rawValue: "timeline.toggle")
    public static let timelineSearch = CommandID(rawValue: "timeline.search")
    public static let timelineCopy = CommandID(rawValue: "timeline.copy")
    public static let timelineCopyCall = CommandID(rawValue: "timeline.copyCall")
    /// F9: what acts only while the timeline is open.
    public static let timelineContextual: Set<CommandID> = [timelineCopyCall]
    public static let timeline: [CommandID] = [timelineToggle, timelineSearch, timelineCopy, timelineCopyCall]
    /// F8.5: ⌘O, the recent projects; and writing the repo's `.smalti/layout.json`.
    public static let projectRecent = CommandID(rawValue: "project.recent")
    public static let projectSave = CommandID(rawValue: "project.save")
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
    /// F5.5: opens the image of the visible preview card in Quick Look; without a card it does nothing.
    public static let previewQuickLook = CommandID(rawValue: "preview.quickLook")

    // F7.5: agent guards.
    /// Approves or rejects the oldest command waiting in the focused pane.
    public static let guardApprove = CommandID(rawValue: "guard.approve")
    public static let guardReject = CommandID(rawValue: "guard.reject")
    /// Writes or removes Smalti's deny rules in the focused pane's project.
    public static let secretsProtect = CommandID(rawValue: "secrets.protect")
    public static let secretsUnprotect = CommandID(rawValue: "secrets.unprotect")

    private static let guardApprovePrefix = "guard.approve."
    private static let guardRejectPrefix = "guard.reject."

    /// ⌘K: approves one waiting command, wherever it is.
    public static func guardApprove(id: UUID) -> CommandID {
        CommandID(rawValue: guardApprovePrefix + id.uuidString)
    }

    public static func guardReject(id: UUID) -> CommandID {
        CommandID(rawValue: guardRejectPrefix + id.uuidString)
    }

    /// The approval this command decides, if it names one.
    public var approval: ApprovalCommand? {
        if rawValue.hasPrefix(Self.guardApprovePrefix) {
            return UUID(uuidString: String(rawValue.dropFirst(Self.guardApprovePrefix.count))).map { .approve($0) }
        }
        if rawValue.hasPrefix(Self.guardRejectPrefix) {
            return UUID(uuidString: String(rawValue.dropFirst(Self.guardRejectPrefix.count))).map { .reject($0) }
        }
        return nil
    }

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
    private static let layoutExportPrefix = "layout.export:"
    private static let editorOpenPrefix = "editor.open:"
    private static let projectOpenPrefix = "project.open:"

    /// F8.5: opens (or jumps to) the project at `root`. Not bindable: ⌘K and ⌘O offer it.
    public static func projectOpen(root: String) -> CommandID { CommandID(rawValue: projectOpenPrefix + root) }

    /// The project root of a `projectOpen` command.
    public var projectRoot: String? {
        rawValue.hasPrefix(Self.projectOpenPrefix) ? String(rawValue.dropFirst(Self.projectOpenPrefix.count)) : nil
    }

    /// F6: opens a file the pane's Claude edited, at its line (`editor.open:<line>:<path>`).
    public static func editorOpen(path: String, line: Int) -> CommandID {
        CommandID(rawValue: "\(editorOpenPrefix)\(line):\(path)")
    }

    public var editorTarget: EditorTarget? {
        guard rawValue.hasPrefix(Self.editorOpenPrefix) else { return nil }
        let rest = rawValue.dropFirst(Self.editorOpenPrefix.count)
        guard let colon = rest.firstIndex(of: ":"), let line = Int(rest[..<colon]) else { return nil }
        return EditorTarget(path: String(rest[rest.index(after: colon)...]), line: line, column: nil)
    }

    public static func layoutSave(_ name: LayoutName) -> CommandID {
        CommandID(rawValue: layoutSavePrefix + name.rawValue)
    }

    public static func layoutRestore(_ name: LayoutName) -> CommandID {
        CommandID(rawValue: layoutRestorePrefix + name.rawValue)
    }

    /// F7: writes a saved layout as a shared file.
    public static func layoutExport(_ name: LayoutName) -> CommandID {
        CommandID(rawValue: layoutExportPrefix + name.rawValue)
    }

    /// The saved-layout action this command stands for, if any.
    public var namedLayout: NamedLayoutCommand? {
        if rawValue.hasPrefix(Self.layoutSavePrefix) {
            return (try? LayoutName(String(rawValue.dropFirst(Self.layoutSavePrefix.count)))).map { .save($0) }
        }
        if rawValue.hasPrefix(Self.layoutRestorePrefix) {
            return (try? LayoutName(String(rawValue.dropFirst(Self.layoutRestorePrefix.count)))).map { .restore($0) }
        }
        if rawValue.hasPrefix(Self.layoutExportPrefix) {
            return (try? LayoutName(String(rawValue.dropFirst(Self.layoutExportPrefix.count)))).map { .export($0) }
        }
        return nil
    }

    /// Every command the app ships, bound or not.
    public static let allStandard: [CommandID] =
        [
            paletteOpen, layoutDwindle, layoutColumns, layoutMaster, panesEqualize, paneNew, paneClose,
            workspaceNew, workspaceRename, workspaceClose, configReload, agentJump, observatoryToggle,
            observatoryPeriod, historySearch, harnessSearch, editorOpenBeside, editorOpenLastEdited, observatoryFilter,
            layoutImport, guardApprove, guardReject, secretsProtect, secretsUnprotect, projectRecent, projectSave,
        ]
        + basics
        + appearance
        + [previewQuickLook, updatesCheck, updatesAutomatic, helpDocs, appSupport, helpWelcome, helpPrivacy]
        + processes
        + timeline
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

/// F7.5: what a ⌘K approval entry does.
public enum ApprovalCommand: Equatable, Sendable {
    case approve(UUID)
    case reject(UUID)
}

public enum NamedLayoutCommand: Equatable, Sendable {
    case save(LayoutName)
    case restore(LayoutName)
    case export(LayoutName)
}
