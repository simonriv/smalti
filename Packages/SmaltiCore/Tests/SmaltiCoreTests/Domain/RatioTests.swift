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
}
