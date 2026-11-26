import SmaltiCore
import Testing

@Suite("NicePriority")
struct NicePriorityTests {
    @Test(arguments: [(Int32(0), Int32(5)), (5, 10), (10, 15), (15, 20), (3, 8), (17, 20), (-5, 0), (-20, 0)])
    func nextStepIsLowerPriority(current: Int32, next: Int32) {
        #expect(NicePriority.next(after: current) == next)
    }

    @Test func lowestHasNoNextStep() {
        #expect(NicePriority.next(after: 20) == nil)
    }

    @Test(arguments: [
        (Int32(-3), PriorityLevel.high), (0, .normal), (1, .low), (9, .low), (10, .lowest), (20, .lowest),
    ])
    func levelOfNice(nice: Int32, level: PriorityLevel) {
        #expect(NicePriority.level(of: nice) == level)
    }
}
