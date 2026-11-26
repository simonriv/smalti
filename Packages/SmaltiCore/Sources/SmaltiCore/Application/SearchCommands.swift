/// Ranks the commands the palette offers for the current state against what the user typed.
@MainActor
public struct SearchCommands {
    private let layouts: LayoutCatalog
    private let texts: CommandTexts

    public init(layouts: LayoutCatalog, texts: CommandTexts) {
        self.layouts = layouts
        self.texts = texts
    }

    /// Saving under the typed name comes last, so typing a command still finds it first.
    public func execute(_ query: String, state: CatalogState, keymap: Keymap) -> [RankedCommand] {
        let ranked = fuzzyMatch(
            query, in: CommandCatalog.commands(for: state, keymap: keymap, layouts: layouts, texts: texts))
        guard let save = CommandCatalog.saveCommand(named: query, texts: texts) else { return ranked }
        return ranked + [RankedCommand(command: save, score: 0)]
    }
}
