import SmaltiCore
import Testing

/// Block 4 review: the scrollback search's count, and selecting the first match exactly once per query.
@Suite("SearchProgress")
struct SearchProgressTests {
    @Test func nothingBeforeTheFirstCount() {
        #expect(SearchProgress().text == "")
    }

    @Test func noMatchesSaySinResultados() {
        #expect(SearchProgress().total(0).progress.text == "Sin resultados")
    }

    @Test func theFirstTotalAsksForTheFirstMatchOnce() {
        let first = SearchProgress().total(3)
        let again = first.progress.total(5)

        #expect(first.selectsFirstMatch)
        #expect(!again.selectsFirstMatch)
    }

    @Test func aLostSelectionDoesNotMoveTheView() {
        let selected = SearchProgress().total(3).progress.selected(0).selected(nil)

        #expect(!selected.total(4).selectsFirstMatch)
    }

    @Test func aNewQueryAsksAgain() {
        let used = SearchProgress().total(3).progress.selected(0)

        #expect(used.newQuery().total(2).selectsFirstMatch)
    }

    /// Final review: between the total and the first selection, never "0 de N".
    @Test func noSelectionYetShowsADash() {
        #expect(SearchProgress().total(6).progress.text == "– de 6")
    }

    @Test func countIsOneBased() {
        #expect(SearchProgress().total(6).progress.selected(0).text == "1 de 6")
    }
}
