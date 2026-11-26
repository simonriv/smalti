/// The scrollback search's state as the bar shows it (F4.5): libghostty reports the total and the selected match
/// separately, the total several times while it scans; the first match is selected once per query.
public struct SearchProgress: Equatable, Sendable {
    private var totalMatches: Int?
    private var selectedMatch: Int?
    private var hasAskedForFirstMatch = false

    public init() {}

    /// "2 de 3", "– de 3" until a match is selected, "Sin resultados", or nothing before the first count.
    public func text(_ texts: TerminalTexts) -> String {
        guard let totalMatches else { return "" }
        guard totalMatches > 0 else { return texts.noResults }
        guard let selectedMatch else { return texts.unselectedMatch(["total": String(totalMatches)]) }
        return texts.selectedMatch(["index": String(selectedMatch + 1), "total": String(totalMatches)])
    }

    /// A new total; `selectsFirstMatch` says whether to go to the first match now.
    public func total(_ count: Int?) -> (progress: SearchProgress, selectsFirstMatch: Bool) {
        var updated = self
        updated.totalMatches = count
        let selects = (count ?? 0) > 0 && !hasAskedForFirstMatch
        if selects { updated.hasAskedForFirstMatch = true }
        return (updated, selects)
    }

    public func selected(_ index: Int?) -> SearchProgress {
        var updated = self
        updated.selectedMatch = index
        return updated
    }

    /// The user changed the text: counts start over and the first match will be selected again.
    public func newQuery() -> SearchProgress {
        SearchProgress()
    }
}
