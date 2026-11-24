import SmaltiCore
import Testing

/// Spec F5: the three styles turn segments and the symbol into lines of runs.
@Suite("Prompt styles")
struct PromptStylesTests {
    private let directory = PromptSegment(
        module: .directory, icon: .folder, runs: [ColoredText("solen/apps/api", .accent)])
    private let branch = PromptSegment(module: .gitBranch, icon: .branch, runs: [ColoredText("main", .ansi(5))])
    private let status = PromptSegment(
        module: .gitStatus, icon: nil,
        runs: [ColoredText("●2", .ansi(3)), ColoredText(" ", .secondary), ColoredText("+1", .ansi(2))],
        attachesTo: .gitBranch)
    private let ok = SymbolSegment(symbol: .chevron, lastExit: 0)

    private func text(_ line: [StyledRun]) -> String {
        line.map { run in
            switch run.content {
            case .text(let text): text
            case .icon(let icon): "<\(icon)>"
            case .symbol(let symbol): symbol.rawValue
            }
        }.joined()
    }

    @Test func cleanTwoLinesPutsContextAboveSymbol() {
        let lines = CleanStyle().lines([directory, branch], symbol: ok, layout: .twoLines)

        #expect(lines.map(text) == ["<folder> solen/apps/api   <branch> main", "› "])
    }

    @Test func cleanOneLineEndsWithSymbol() {
        let lines = CleanStyle().lines([directory], symbol: ok, layout: .oneLine)

        #expect(lines.map(text) == ["<folder> solen/apps/api › "])
    }

    @Test func gitStatusJoinsBranchWithOneSpace() {
        let lines = CleanStyle().lines([branch, status], symbol: ok, layout: .twoLines)

        #expect(lines.first.map(text) == "<branch> main ●2 +1")
    }

    @Test func exitNonZeroColorsSymbolAndAddsExitText() {
        let lines = CleanStyle().lines([], symbol: SymbolSegment(symbol: .chevron, lastExit: 1), layout: .twoLines)
        let symbolLine = lines.last ?? []

        #expect(text(symbolLine) == "› exit 1 ")
        #expect(symbolLine.first?.color == .failed)
        #expect(symbolLine.dropFirst().first { text([$0]).contains("exit") }?.color == .secondary)
    }

    @Test func successSymbolUsesAccent() {
        #expect(CleanStyle().lines([], symbol: ok, layout: .twoLines).last?.first?.color == .accent)
    }

    @Test func noSegmentsInTwoLinesLeavesOnlySymbol() {
        #expect(CleanStyle().lines([], symbol: ok, layout: .twoLines).map(text) == ["› "])
    }

    @Test func pillsWrapEachSegmentWithItsTint() {
        let line = PillsStyle().lines([directory, branch], symbol: ok, layout: .oneLine).first ?? []
        let tinted = line.filter { $0.background != nil }

        #expect(text(line) == " <folder> solen/apps/api   <branch> main  › ")
        #expect(Set(tinted.compactMap(\.background)) == [.accent, .ansi(5)])
    }

    @Test func pillsMixBackgroundAt16Percent() {
        let accent = RGBAColor(red: 122, green: 162, blue: 247, alpha: 1)
        let panel = RGBAColor(red: 6, green: 7, blue: 10, alpha: 1)

        let background = PillsStyle.background(of: accent, over: panel)

        #expect(background == panel.underneath(accent.withAlpha(0.16)))
        #expect(background.alpha == 1)
    }

    @Test func symbolOnlyLineHasOnlySymbol() {
        let lines = SymbolOnlyStyle().lines([directory, branch], symbol: ok, layout: .twoLines)

        #expect(lines.map(text) == ["› "])
    }

    @Test(arguments: PromptStyleID.allCases)
    func everyStyleIdHasItsStyle(_ id: PromptStyleID) {
        #expect(PromptStyles.style(for: id).id == id)
    }
}
