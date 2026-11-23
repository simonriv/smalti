/// Ranks the commands the palette offers for the current state against what the user typed.
@MainActor
public struct SearchCommands {
    private let layouts: LayoutCatalog

    public init(layouts: LayoutCatalog) {
        self.layouts = layouts
    }

    /// Saving under the typed name comes last, so typing a command still finds it first.
    public func execute(
        _ query: String, set: WorkspaceSet, keymap: Keymap, savedLayouts: [NamedLayoutSummary] = []
    ) -> [RankedCommand] {
        let ranked = fuzzyMatch(
            query, in: CommandCatalog.commands(for: set, keymap: keymap, layouts: layouts, savedLayouts: savedLayouts))
        guard let save = CommandCatalog.saveCommand(named: query) else { return ranked }
        return ranked + [RankedCommand(command: save, score: 0)]
    }
}
