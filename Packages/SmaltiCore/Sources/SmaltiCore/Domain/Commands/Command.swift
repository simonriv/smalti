/// Section of the command palette a command is listed under.
/// Its title is in `CommandTexts.groups`.
public enum CommandGroup: String, Sendable {
    /// F7.5: commands Smalti holds until the user decides.
    case approvals
    /// F8.5: the repos with `.smalti/layout.json`.
    case projects
    case tiling
    case panes
    case workspaces
    case configuration
    case windows
    case terminal
    case help
    /// F6: the files the focused pane's Claude wrote.
    case editedFiles
}

/// One entry of the command palette: what the user can do right now.
public struct Command: Hashable, Sendable {
    public let id: CommandID
    public let title: String
    public let subtitle: String?
    public let group: CommandGroup
    public let shortcut: KeyChord?
    /// Whether the command describes the state already in effect, such as the active layout.
    public let isCurrent: Bool
    /// Board icon, when the board draws one.
    public let icon: CommandIcon?

    public init(
        id: CommandID, title: String, subtitle: String?, group: CommandGroup, shortcut: KeyChord?,
        isCurrent: Bool, icon: CommandIcon? = nil
    ) {
        self.icon = icon
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.shortcut = shortcut
        self.isCurrent = isCurrent
    }
}
