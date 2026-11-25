import SmaltiCore
import Testing

/// F7.6: how a stored format version compares with the one this build understands.
@Suite("FormatCompatibility")
struct FormatCompatibilityTests {
    @Test func missingVersionCountsAsOne() {
        #expect(FormatCompatibility.of(stored: nil, current: 1) == .current)
    }

    @Test func missingVersionIsOlderThanTwo() {
        #expect(FormatCompatibility.of(stored: nil, current: 2) == .older(1))
    }

    @Test func sameVersionIsCurrent() {
        #expect(FormatCompatibility.of(stored: 2, current: 2) == .current)
    }

    @Test func lowerVersionIsOlder() {
        #expect(FormatCompatibility.of(stored: 1, current: 2) == .older(1))
    }

    @Test func higherVersionIsNewer() {
        #expect(FormatCompatibility.of(stored: 3, current: 2) == .newer(3))
    }

    @Test func oneAboveIsNewer() {
        #expect(FormatCompatibility.of(stored: 2, current: 1) == .newer(2))
    }

    @Test func zeroIsOlder() {
        #expect(FormatCompatibility.of(stored: 0, current: 2) == .older(0))
    }

    @Test func onlyNewerIsNewer() {
        #expect(FormatCompatibility.newer(3).isNewer)
        #expect(!FormatCompatibility.current.isNewer)
        #expect(!FormatCompatibility.older(1).isNewer)
    }
}
