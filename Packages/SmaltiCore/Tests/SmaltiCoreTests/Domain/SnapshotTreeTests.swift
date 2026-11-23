import SmaltiCore
import Testing

@Suite("SnapshotTree")
struct SnapshotTreeTests {
    private let a = PaneID()
    private let b = PaneID()
    private let c = PaneID()

    private var editedDwindle: LayoutTree {
        .split(
            axis: .sideBySide, ratio: Ratio(0.7), first: .leaf(a),
            second: .split(axis: .stacked, ratio: Ratio(0.3), first: .leaf(b), second: .leaf(c)))
    }

    @Test func treeRoundTripsThroughIndices() {
        let fresh = [PaneID(), PaneID(), PaneID()]

        let restored = SnapshotTree(editedDwindle, order: [a, b, c]).layoutTree(ids: fresh)

        #expect(
            restored
                == .split(
                    axis: .sideBySide, ratio: Ratio(0.7), first: .leaf(fresh[0]),
                    second: .split(axis: .stacked, ratio: Ratio(0.3), first: .leaf(fresh[1]), second: .leaf(fresh[2]))))
    }

    @Test func treeWithUnknownIndexYieldsNil() {
        let snapshot = SnapshotTree(editedDwindle, order: [a, b, c])

        #expect(snapshot.layoutTree(ids: [PaneID(), PaneID()]) == nil)
    }

    @Test func paneMissingFromOrderYieldsNilOnRestore() {
        let snapshot = SnapshotTree(editedDwindle, order: [a, b])

        #expect(snapshot.layoutTree(ids: [PaneID(), PaneID(), PaneID()]) == nil)
    }
}
