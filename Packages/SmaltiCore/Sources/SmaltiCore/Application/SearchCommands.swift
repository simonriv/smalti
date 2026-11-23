/// Ranks the commands the palette offers for the current state against what the user typed.
@MainActor
public struct SearchCommands {
    private let layouts: LayoutCatalog

    public init(layouts: LayoutCatalog) {
        self.layouts = layouts
    }

    public func execute(_ query: String, set: WorkspaceSet, keymap: Keymap) -> [RankedCommand] {
        fuzzyMatch(query, in: CommandCatalog.commands(for: set, keymap: keymap, layouts: layouts))
    }
}
