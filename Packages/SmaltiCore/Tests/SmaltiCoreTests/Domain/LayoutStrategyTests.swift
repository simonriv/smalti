import SmaltiCore
import Testing

@Suite("Layout strategies")
struct LayoutStrategyTests {
    private let area = Rect(x: 0, y: 0, width: 1328, height: 752).insetBy(10)
    private let gap = 8.0

    private func makePanes(_ count: Int) -> [PaneID] {
        (0..<count).map { _ in PaneID() }
    }

    private func frames(of strategy: any LayoutStrategy, _ panes: [PaneID]) -> [PaneID: Rect] {
        strategy.tree(for: panes)?.frames(in: area, gap: gap) ?? [:]
    }

    @Test(arguments: 1...9)
    func everyStrategyKeepsAllPanesInOrder(count: Int) {
        let panes = makePanes(count)

        for strategy in LayoutCatalog.standard.all {
            #expect(strategy.tree(for: panes)?.panes == panes, "\(strategy.displayName)")
        }
    }

    @Test(arguments: 1...9)
    func everyStrategyFillsTheAreaWithoutOverlap(count: Int) {
        let panes = makePanes(count)

        for strategy in LayoutCatalog.standard.all {
            let placed = frames(of: strategy, panes)
            #expect(placed.count == count, "\(strategy.displayName)")
            for frame in placed.values {
                #expect(frame.minX >= area.minX - frameTolerance)
                #expect(frame.maxX <= area.maxX + frameTolerance)
                #expect(frame.minY >= area.minY - frameTolerance)
                #expect(frame.maxY <= area.maxY + frameTolerance)
            }
            expectNoOverlap(Array(placed.values), "\(strategy.displayName)")
        }
    }

    private func expectNoOverlap(
        _ frames: [Rect], _ label: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (index, first) in frames.enumerated() {
            for second in frames.dropFirst(index + 1) {
                let overlapWidth = min(first.maxX, second.maxX) - max(first.minX, second.minX)
                let overlapHeight = min(first.maxY, second.maxY) - max(first.minY, second.minY)
                let overlapArea = max(0, overlapWidth) * max(0, overlapHeight)
                #expect(overlapArea <= 0, "\(label)", sourceLocation: sourceLocation)
            }
        }
    }

    @Test(arguments: [5, 9])
    func columnsAreEqualForFiveAndNine(count: Int) {
        let panes = makePanes(count)

        let placed = frames(of: ColumnsLayout(), panes)

        let widths = panes.compactMap { placed[$0]?.size.width }
        #expect(widths.count == count)
        for width in widths {
            #expect(abs(width - widths[0]) < frameTolerance)
        }
    }

    @Test func everyStrategyProducesNilForNoPanes() {
        for strategy in LayoutCatalog.standard.all {
            #expect(strategy.tree(for: []) == nil, "\(strategy.displayName)")
        }
    }

    @Test func dwindleWithThreeMatchesMainBoard() {
        let panes = makePanes(3)

        let placed = frames(of: DwindleLayout(), panes)

        expectFrame(placed[panes[0]], x: 10, y: 10, width: 746.81, height: 732)
        expectFrame(placed[panes[1]], x: 764.81, y: 10, width: 553.19, height: 362)
        expectFrame(placed[panes[2]], x: 764.81, y: 380, width: 553.19, height: 362)
    }

    @Test func masterWithThreeMatchesMainBoard() {
        let panes = makePanes(3)

        let placed = frames(of: MasterStackLayout(), panes)

        expectFrame(placed[panes[0]], x: 10, y: 10, width: 1308, height: 387.26)
        expectFrame(placed[panes[1]], x: 10, y: 405.26, width: 650, height: 336.74)
        expectFrame(placed[panes[2]], x: 668, y: 405.26, width: 650, height: 336.74)
    }

    @Test func columnsWithThreeAreEqual() {
        let panes = makePanes(3)

        let placed = frames(of: ColumnsLayout(), panes)

        expectFrame(placed[panes[0]], x: 10, y: 10, width: 430.67, height: 732)
        expectFrame(placed[panes[1]], x: 448.67, y: 10, width: 430.67, height: 732)
        expectFrame(placed[panes[2]], x: 887.33, y: 10, width: 430.67, height: 732)
    }

    @Test func dwindleAlternatesAxis() {
        let panes = makePanes(4)
        let (a, b, c, d) = (panes[0], panes[1], panes[2], panes[3])

        let tree = DwindleLayout().tree(for: panes)

        guard case .split(.sideBySide, let outer, .leaf(a), let right)? = tree,
            case .split(.stacked, let middle, .leaf(b), let bottom) = right,
            case .split(.sideBySide, let inner, .leaf(c), .leaf(d)) = bottom
        else {
            Issue.record("expected a | (b / (c | d)), got \(String(describing: tree))")
            return
        }
        #expect(abs(outer.value - 1.35 / 2.35) < 1e-9)
        #expect(middle == .half)
        #expect(inner == .half)
    }

    @Test func masterWithOnePaneIsALeaf() {
        let pane = PaneID()

        #expect(MasterStackLayout().tree(for: [pane]) == .leaf(pane))
    }

    @Test func masterWithFourSharesTheStackEqually() {
        let panes = makePanes(4)

        let placed = frames(of: MasterStackLayout(), panes)

        let widths = panes.dropFirst().compactMap { placed[$0]?.size.width }
        #expect(widths.count == 3)
        for width in widths {
            #expect(abs(width - widths[0]) < frameTolerance)
        }
    }

    @Test func strategiesHaveSpanishNamesForTheInterface() {
        let names = LayoutCatalog.standard.all.map { [$0.displayName, $0.statusName] }

        #expect(names == [["Dwindle", "dwindle"], ["Columnas", "columnas"], ["Maestro + pila", "maestro"]])
    }

    @Test func catalogFindsStrategiesById() {
        let catalog = LayoutCatalog.standard

        #expect(catalog.strategy(for: .dwindle)?.id == .dwindle)
        #expect(catalog.strategy(for: .columns)?.id == .columns)
        #expect(catalog.strategy(for: .master)?.id == .master)
        #expect(catalog.strategy(for: LayoutID(rawValue: "unknown")) == nil)
    }

    @Test func catalogOrderIsDwindleColumnsMaster() {
        let ids = LayoutCatalog.standard.all.map(\.id)

        #expect(ids == [.dwindle, .columns, .master])
    }
}
