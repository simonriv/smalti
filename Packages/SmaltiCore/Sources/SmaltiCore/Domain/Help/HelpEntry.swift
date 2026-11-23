/// One row of the help: what it does, how to do it, and the command ↩ runs, if any.
public struct HelpEntry: Equatable, Sendable {
    public let title: String
    /// "⌘N", "⌘1…⌘9", "⌥⌘←→↑↓", "en ⌘K", "Tab", "arrastrar".
    public let keys: String
    /// What ↩ runs; nil for families (⌘1…⌘9) and for keys that are not Smalti's (Tab, ⌘clic).
    public let command: CommandID?
    /// Every command the row stands for, so the help can prove it lists them all.
    public let covers: [CommandID]

    public init(title: String, keys: String, command: CommandID?, covers: [CommandID]) {
        self.title = title
        self.keys = keys
        self.command = command
        self.covers = covers
    }
}

public struct HelpSection: Equatable, Sendable {
    public let title: String
    public let entries: [HelpEntry]

    public init(title: String, entries: [HelpEntry]) {
        self.title = title
        self.entries = entries
    }
}
