import SmaltiCore
import Testing

@Suite("Geometry")
struct GeometryTests {
    @Test func insetShrinksEverySide() {
        let rect = Rect(x: 0, y: 0, width: 100, height: 50)

        let inset = rect.insetBy(10)

        #expect(inset == Rect(x: 10, y: 10, width: 80, height: 30))
    }

    @Test func insetNeverProducesNegativeSize() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)

        let inset = rect.insetBy(20)

        #expect(inset.size == Size(width: 0, height: 0))
    }

    @Test func collapsedInsetStaysCenteredInsideOriginal() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)

        let inset = rect.insetBy(20)

        #expect(inset == Rect(x: 5, y: 5, width: 0, height: 0))
    }

    @Test func rectExposesEdgesAndMidpoints() {
        let rect = Rect(x: 10, y: 20, width: 100, height: 50)

        #expect(rect.minX == 10)
        #expect(rect.maxX == 110)
        #expect(rect.minY == 20)
        #expect(rect.maxY == 70)
        #expect(rect.midX == 60)
        #expect(rect.midY == 45)
    }

    @Test func directionMapsToAxis() {
        #expect(Direction.left.axis == .sideBySide)
        #expect(Direction.right.axis == .sideBySide)
        #expect(Direction.up.axis == .stacked)
        #expect(Direction.down.axis == .stacked)
    }

    @Test func directionPointsTowardSecondOnlyForRightAndDown() {
        #expect(Direction.right.pointsTowardSecond)
        #expect(Direction.down.pointsTowardSecond)
        #expect(!Direction.left.pointsTowardSecond)
        #expect(!Direction.up.pointsTowardSecond)
    }
}
