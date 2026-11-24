import Testing

@testable import GhosttyAdapter

/// Final review: VoiceOver hears new output — the focused terminal announces a change at most once per sample.
struct VisibleTextWatchTests {
    @Test func firstSampleOnlyRemembersTheText() {
        var watch = VisibleTextWatch()

        let changed = watch.hasChanged("% ls")

        #expect(!changed)
    }

    @Test func sameTextIsNotAChange() {
        var watch = VisibleTextWatch()
        _ = watch.hasChanged("% ls")

        let changed = watch.hasChanged("% ls")

        #expect(!changed)
    }

    @Test func newOutputIsAChange() {
        var watch = VisibleTextWatch()
        _ = watch.hasChanged("% ls")

        let changed = watch.hasChanged("% ls\nREADME.md")

        #expect(changed)
    }

    @Test func forgettingStartsOver() {
        var watch = VisibleTextWatch()
        _ = watch.hasChanged("% ls")
        watch.forget()

        let changed = watch.hasChanged("% pwd")

        #expect(!changed)
    }

    @Test func sampleIntervalIsHalfASecond() {
        #expect(VisibleTextWatch.interval == 0.5)
    }
}
