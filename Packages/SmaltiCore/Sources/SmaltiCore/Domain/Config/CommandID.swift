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
    public static let claudeIntegrationInstall = CommandID(rawValue: "claude.integration.install")
    public static let claudeIntegrationUninstall = CommandID(rawValue: "claude.integration.uninstall")

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
            workspaceNew, workspaceRename, workspaceClose, configReload,
        ]
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
