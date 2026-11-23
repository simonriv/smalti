import SmaltiCore
import Testing

/// The palette builds only the rows that fit; this window decides which ones as the selection moves.
@Suite("Result window")
struct ResultWindowTests {
    @Test func startsAtTheTopWithTheFirstSelected() {
        let window = ResultWindow(count: 40, capacity: 10)

        #expect(window.selection == 0)
        #expect(window.visible == 0..<10)
    }

    @Test func fewerResultsThanCapacityShowAll() {
        #expect(ResultWindow(count: 3, capacity: 10).visible == 0..<3)
    }

    @Test func noResultsShowNothing() {
        let window = ResultWindow(count: 0, capacity: 10)

        #expect(window.visible.isEmpty)
        #expect(window.moving(by: 1).selection == 0)
    }

    @Test func movingPastTheBottomScrollsByOne() {
        var window = ResultWindow(count: 40, capacity: 10)
        for _ in 0..<10 { window = window.moving(by: 1) }

        #expect(window.selection == 10)
        #expect(window.visible == 1..<11)
    }

    @Test func movingAboveTheTopScrollsBack() {
        var window = ResultWindow(count: 40, capacity: 10)
        for _ in 0..<12 { window = window.moving(by: 1) }
        for _ in 0..<12 { window = window.moving(by: -1) }

        #expect(window.selection == 0)
        #expect(window.visible == 0..<10)
    }

    @Test func upFromTheFirstWrapsToTheLast() {
        let window = ResultWindow(count: 40, capacity: 10).moving(by: -1)

        #expect(window.selection == 39)
        #expect(window.visible == 30..<40)
    }

    @Test func downFromTheLastWrapsToTheFirst() {
        let window = ResultWindow(count: 40, capacity: 10).moving(by: -1).moving(by: 1)

        #expect(window.selection == 0)
        #expect(window.visible == 0..<10)
    }

    @Test func capacityBelowOneStillShowsOneRow() {
        #expect(ResultWindow(count: 5, capacity: 0).visible == 0..<1)
    }
}
