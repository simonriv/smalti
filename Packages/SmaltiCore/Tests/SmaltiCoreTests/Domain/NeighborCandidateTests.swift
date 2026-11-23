@testable import SmaltiCore
import Testing

@Suite("NeighborCandidate")
struct NeighborCandidateTests {
    private let origin = Rect(x: 10, y: 20, width: 100, height: 50)

    @Test func rightDistanceIsTheGapAfterTheOriginRightEdge() {
        let frame = Rect(x: 118, y: 20, width: 100, height: 50)

        let candidate = NeighborCandidate(id: PaneID(), frame: frame, origin: origin, direction: .right)

        #expect(candidate.distance == 8)
    }

    @Test func downDistanceIsTheGapAfterTheOriginBottomEdge() {
        let frame = Rect(x: 10, y: 78, width: 100, height: 50)

        let candidate = NeighborCandidate(id: PaneID(), frame: frame, origin: origin, direction: .down)

        #expect(candidate.distance == 8)
    }
}
