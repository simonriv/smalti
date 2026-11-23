import SmaltiCore
import Testing

@Suite("Ratio")
struct RatioTests {
    @Test func ratioClampsBelowMinimum() {
        #expect(Ratio(0.02).value == 0.1)
    }

    @Test func ratioClampsAboveMaximum() {
        #expect(Ratio(0.95).value == 0.9)
    }

    @Test func ratioKeepsValuesInsideBounds() {
        #expect(Ratio(0.574).value == 0.574)
    }

    @Test func halfIsOneHalf() {
        #expect(Ratio.half.value == 0.5)
    }

    @Test func addingClampsAtTheEdge() {
        #expect(Ratio(0.88).adding(0.05).value == 0.9)
    }

    @Test func addingInsideBoundsMovesByDelta() {
        #expect(abs(Ratio(0.5).adding(0.05).value - 0.55) < 1e-9)
    }

    @Test func addingNegativeClampsAtLowerBound() {
        #expect(Ratio(0.12).adding(-0.05).value == 0.1)
    }

    @Test func boundsAreTenToNinetyPercent() {
        #expect(Ratio.bounds == 0.1...0.9)
    }

    @Test func nanBecomesHalf() {
        #expect(Ratio(.nan) == Ratio.half)
    }
}
