import SmaltiCore
import Testing

@Suite("LayoutTree editing")
struct LayoutTreeEditingTests {
    private let a = PaneID()
    private let b = PaneID()
    private let c = PaneID()
    private let wideArea = Rect(x: 0, y: 0, width: 2008, height: 1008)

    private var wideGeometry: LayoutGeometry { .standard(area: wideArea) }

    private func sideBySide(_ ratio: Double, _ first: LayoutTree, _ second: LayoutTree) -> LayoutTree {
        .split(axis: .sideBySide, ratio: Ratio(ratio), first: first, second: second)
    }

    private func stacked(_ ratio: Double, _ first: LayoutTree, _ second: LayoutTree) -> LayoutTree {
        .split(axis: .stacked, ratio: Ratio(ratio), first: first, second: second)
    }

    /// a on the left; b over c on the right.
    private var dwindle: LayoutTree {
        sideBySide(0.5, .leaf(a), stacked(0.5, .leaf(b), .leaf(c)))
    }

    /// a as master on the left; b over c in the stack on the right.
    private var master: LayoutTree { dwindle }

    private func ratio(of tree: LayoutTree) -> Double? {
        guard case .split(_, let ratio, _, _) = tree else { return nil }
        return ratio.value
    }

    private func request(_ pane: PaneID, _ direction: Direction) -> ResizeRequest {
        ResizeRequest(pane: pane, direction: direction, step: ResizeRequest.defaultStep)
    }

    @Test func resizeRightGrowsFirstChild() {
        let tree = sideBySide(0.5, .leaf(a), .leaf(b))

        let resized = tree.resizing(request(a, .right), within: wideGeometry)

        #expect(abs((ratio(of: resized) ?? 0) - 0.55) < 1e-9)
    }

    @Test func resizeLeftFromSecondChildShrinksFirst() {
        let tree = sideBySide(0.5, .leaf(a), .leaf(b))

        let resized = tree.resizing(request(b, .left), within: wideGeometry)

        #expect(abs((ratio(of: resized) ?? 0) - 0.45) < 1e-9)
    }

    @Test func resizeStopsAtRatioBounds() {
        let tree = sideBySide(0.9, .leaf(a), .leaf(b))

        let resized = tree.resizing(request(a, .right), within: wideGeometry)

        #expect(ratio(of: resized) == 0.9)
    }

    @Test func resizeRefusedWhenNeighborWouldBreakMinimum() {
        let tree = sideBySide(0.55, .leaf(a), .leaf(b))
        let geometry = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 600, height: 500))

        let resized = tree.resizing(request(a, .right), within: geometry)

        #expect(resized == tree)
    }

    @Test func resizeWithoutMatchingAncestorDoesNothing() {
        let tree = sideBySide(0.5, .leaf(a), .leaf(b))

        let resized = tree.resizing(request(a, .down), within: wideGeometry)

        #expect(resized == tree)
    }

    @Test func resizeWithoutEdgeTowardDirectionDoesNothing() {
        let tree = sideBySide(0.5, .leaf(a), .leaf(b))

        let resized = tree.resizing(request(b, .right), within: wideGeometry)

        #expect(resized == tree)
    }

    @Test func resizeUsesNearestAncestorWithAnEdge() {
        let tree = dwindle

        let resized = tree.resizing(request(b, .down), within: wideGeometry)

        guard case .split(_, let outer, _, let inner) = resized else {
            Issue.record("expected a split")
            return
        }
        #expect(outer.value == 0.5)
        #expect(abs((ratio(of: inner) ?? 0) - 0.55) < 1e-9)
    }

    @Test func resizeClimbsPastAncestorsWithoutAnEdge() {
        let tree = stacked(0.5, sideBySide(0.5, .leaf(a), .leaf(b)), .leaf(c))

        let resized = tree.resizing(request(b, .down), within: wideGeometry)

        #expect(abs((ratio(of: resized) ?? 0) - 0.55) < 1e-9)
    }

    @Test func swapExchangesLeavesAndKeepsRatios() {
        let tree = sideBySide(0.3, .leaf(a), stacked(0.7, .leaf(b), .leaf(c)))

        let swapped = tree.swapping(a, c)

        #expect(swapped == sideBySide(0.3, .leaf(c), stacked(0.7, .leaf(b), .leaf(a))))
    }

    @Test func swapWithUnknownPaneChangesNothing() {
        let tree = sideBySide(0.5, .leaf(a), .leaf(b))

        #expect(tree.swapping(a, PaneID()) == tree)
    }

    @Test func neighborToTheRightInDwindle() {
        let neighbor = dwindle.neighbor(of: a, toward: .right, in: wideArea, gap: 8)

        #expect(neighbor == b)
    }

    @Test func neighborDownInStack() {
        let neighbor = master.neighbor(of: b, toward: .down, in: wideArea, gap: 8)

        #expect(neighbor == c)
    }

    @Test func neighborLeftFromStackReturnsMaster() {
        let neighbor = master.neighbor(of: c, toward: .left, in: wideArea, gap: 8)

        #expect(neighbor == a)
    }

    @Test func noNeighborAtTheEdgeReturnsNil() {
        let neighbor = dwindle.neighbor(of: a, toward: .left, in: wideArea, gap: 8)

        #expect(neighbor == nil)
    }

    @Test func neighborOfUnknownPaneIsNil() {
        let neighbor = dwindle.neighbor(of: PaneID(), toward: .right, in: wideArea, gap: 8)

        #expect(neighbor == nil)
    }

    @Test func neighborTieBreaksByOverlap() {
        // a is tall on the left; on the right b is short over a taller c.
        let tree = sideBySide(0.5, .leaf(a), stacked(0.2, .leaf(b), .leaf(c)))
        let area = Rect(x: 0, y: 0, width: 1008, height: 1008)

        let neighbor = tree.neighbor(of: a, toward: .right, in: area, gap: 8)

        #expect(neighbor == c)
    }

    @Test func neighborIgnoresPanesThatDoNotOverlapPerpendicularly() {
        // c spans the full width below a and b, so nothing lies to its right.
        let tree = stacked(0.5, sideBySide(0.5, .leaf(a), .leaf(b)), .leaf(c))

        let neighbor = tree.neighbor(of: c, toward: .right, in: wideArea, gap: 8)

        #expect(neighbor == nil)
    }
}
