import SmaltiCore
import Testing

@Suite("LayoutTree frames")
struct LayoutTreeFramesTests {
    private let tolerance = 0.01
    private let a = PaneID()
    private let b = PaneID()
    private let c = PaneID()
    private let d = PaneID()

    private func expectFrame(
        _ frame: Rect?, x: Double, y: Double, width: Double, height: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let frame else {
            Issue.record("missing frame", sourceLocation: sourceLocation)
            return
        }
        #expect(abs(frame.minX - x) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(frame.minY - y) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(frame.size.width - width) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(frame.size.height - height) < tolerance, sourceLocation: sourceLocation)
    }

    @Test func singleLeafFillsTheArea() {
        let area = Rect(x: 10, y: 20, width: 300, height: 200)

        let frames = LayoutTree.leaf(a).frames(in: area, gap: 8)

        #expect(frames == [a: area])
    }

    @Test func sideBySideSplitHonoursRatioAndGap() {
        let tree = LayoutTree.split(axis: .sideBySide, ratio: .half, first: .leaf(a), second: .leaf(b))

        let frames = tree.frames(in: Rect(x: 0, y: 0, width: 1008, height: 500), gap: 8)

        expectFrame(frames[a], x: 0, y: 0, width: 500, height: 500)
        expectFrame(frames[b], x: 508, y: 0, width: 500, height: 500)
    }

    @Test func stackedSplitHonoursRatioAndGap() {
        let tree = LayoutTree.split(axis: .stacked, ratio: Ratio(0.25), first: .leaf(a), second: .leaf(b))

        let frames = tree.frames(in: Rect(x: 0, y: 0, width: 400, height: 408), gap: 8)

        expectFrame(frames[a], x: 0, y: 0, width: 400, height: 100)
        expectFrame(frames[b], x: 0, y: 108, width: 400, height: 300)
    }

    @Test func panesListsLeavesInOrder() {
        let tree = LayoutTree.split(
            axis: .sideBySide, ratio: .half,
            first: .leaf(a),
            second: .split(axis: .stacked, ratio: .half, first: .leaf(b), second: .leaf(c)))

        #expect(tree.panes == [a, b, c])
    }

    @Test func framesNeverCollapseBelowOnePoint() {
        let ids = (0..<9).map { _ in PaneID() }
        let tree = ids.dropFirst().reduce(LayoutTree.leaf(ids[0])) { partial, id in
            .split(axis: .sideBySide, ratio: .half, first: partial, second: .leaf(id))
        }

        let frames = tree.frames(in: Rect(x: 0, y: 0, width: 40, height: 40), gap: 8)

        #expect(frames.count == 9)
        #expect(frames.values.allSatisfy { $0.size.width >= 1 && $0.size.height >= 1 })
    }

    @Test func columnChainWithSpanRatiosHasEqualWidths() {
        let tree = LayoutTree.split(
            axis: .sideBySide, ratio: Ratio(1.0 / 3.0),
            first: .leaf(a),
            second: .split(axis: .sideBySide, ratio: Ratio(0.5), first: .leaf(b), second: .leaf(c)))

        let frames = tree.frames(in: Rect(x: 0, y: 0, width: 1308, height: 732), gap: 8)

        expectFrame(frames[a], x: 0, y: 0, width: 430.67, height: 732)
        expectFrame(frames[b], x: 438.67, y: 0, width: 430.67, height: 732)
        expectFrame(frames[c], x: 877.33, y: 0, width: 430.67, height: 732)
    }

    @Test func equalizedColumnsHaveEqualWidths() {
        let tree = LayoutTree.split(
            axis: .sideBySide, ratio: Ratio(0.3),
            first: .leaf(a),
            second: .split(
                axis: .sideBySide, ratio: Ratio(0.7),
                first: .leaf(b),
                second: .split(axis: .sideBySide, ratio: Ratio(0.2), first: .leaf(c), second: .leaf(d))))

        let frames = tree.equalized().frames(in: Rect(x: 0, y: 0, width: 1000, height: 400), gap: 8)

        let widths = tree.panes.compactMap { frames[$0]?.size.width }
        #expect(widths.count == 4)
        #expect(widths.allSatisfy { abs($0 - widths[0]) < tolerance })
    }

    @Test func equalizedDwindleBalancesEachAxis() {
        let tree = LayoutTree.split(
            axis: .sideBySide, ratio: Ratio(0.8),
            first: .leaf(a),
            second: .split(axis: .stacked, ratio: Ratio(0.3), first: .leaf(b), second: .leaf(c)))

        let frames = tree.equalized().frames(in: Rect(x: 0, y: 0, width: 900, height: 600), gap: 8)

        #expect(abs((frames[a]?.size.width ?? 0) - (frames[b]?.size.width ?? -1)) < tolerance)
        #expect(abs((frames[b]?.size.height ?? 0) - (frames[c]?.size.height ?? -1)) < tolerance)
    }

    @Test func fitsRejectsFramesBelowMinimum() {
        let tree = LayoutTree.split(axis: .sideBySide, ratio: .half, first: .leaf(a), second: .leaf(b))
        let roomy = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 488, height: 120))
        let cramped = LayoutGeometry.standard(area: Rect(x: 0, y: 0, width: 487, height: 120))

        #expect(roomy.fits(tree))
        #expect(!cramped.fits(tree))
    }
}
