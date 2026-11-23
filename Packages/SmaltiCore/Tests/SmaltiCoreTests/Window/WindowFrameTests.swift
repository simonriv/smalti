import SmaltiCore
import Testing

/// Screen coordinates as AppKit gives them (origin bottom-left, y up). Review Focus 1.
@Suite("WindowFrame")
struct WindowFrameTests {
    private let main = Rect(x: 0, y: 0, width: 1440, height: 900)
    private let right = Rect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func frameOutsideEveryScreenMovesToMain() {
        let lost = Rect(x: 4000, y: 200, width: 800, height: 600)

        let fitted = WindowFrame.fitted(lost, screens: [main], main: main)

        #expect(fitted == Rect(x: 320, y: 150, width: 800, height: 600))
    }

    @Test func frameLargerThanScreenShrinks() {
        let huge = Rect(x: 0, y: 0, width: 2000, height: 1200)

        let fitted = WindowFrame.fitted(huge, screens: [main], main: main)

        #expect(fitted == main)
    }

    @Test func framePartlyVisibleIsKept() {
        let partly = Rect(x: 1000, y: 100, width: 800, height: 600)

        #expect(WindowFrame.fitted(partly, screens: [main], main: main) == partly)
    }

    @Test func frameOnASecondScreenIsKeptWhileItExists() {
        let onRight = Rect(x: 1600, y: 100, width: 800, height: 600)

        #expect(WindowFrame.fitted(onRight, screens: [main, right], main: main) == onRight)
    }

    @Test func barelyVisibleSliverCountsAsLost() {
        let sliver = Rect(x: 1430, y: 100, width: 800, height: 600)

        let fitted = WindowFrame.fitted(sliver, screens: [main], main: main)

        #expect(fitted == Rect(x: 320, y: 150, width: 800, height: 600))
    }

    @Test func largerThanItsOwnScreenShrinksIntoIt() {
        let tooTall = Rect(x: 1500, y: 0, width: 800, height: 1500)

        let fitted = WindowFrame.fitted(tooTall, screens: [main, right], main: main)

        #expect(fitted == Rect(x: 1500, y: 0, width: 800, height: 1080))
    }

    @Test func frameAcrossTwoScreensBelongsToTheOneShowingMore() {
        let tall = Rect(x: 1340, y: 0, width: 800, height: 1000)

        let fitted = WindowFrame.fitted(tall, screens: [main, right], main: main)

        #expect(fitted == Rect(x: 1340, y: 0, width: 800, height: 1000))
    }

    @Test func frameAboveTheTopIsPulledDownToKeepTheTitleBarReachable() {
        let high = Rect(x: 100, y: 500, width: 800, height: 600)

        #expect(WindowFrame.fitted(high, screens: [main], main: main) == Rect(x: 100, y: 300, width: 800, height: 600))
    }

    @Test func screenLeftOfMainWithNegativeOriginKeepsItsWindow() {
        let left = Rect(x: -1920, y: -200, width: 1920, height: 1080)
        let onLeft = Rect(x: -1500, y: 0, width: 800, height: 600)

        #expect(WindowFrame.fitted(onLeft, screens: [main, left], main: main) == onLeft)
    }

    @Test func cascadeStepsDownRight() {
        let front = Rect(x: 100, y: 300, width: 800, height: 600)

        #expect(WindowFrame.cascaded(from: front) == Rect(x: 124, y: 276, width: 800, height: 600))
    }
}
