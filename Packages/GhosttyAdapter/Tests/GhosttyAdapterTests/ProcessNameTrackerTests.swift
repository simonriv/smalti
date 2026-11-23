import SmaltiCore
import Testing

@testable import GhosttyAdapter

@Suite("Process name tracker")
struct ProcessNameTrackerTests {
    @Test func trackerEmitsOnlyOnChange() {
        var tracker = ProcessNameTracker()

        let events = ["zsh", "zsh", "sleep", "zsh"].map { tracker.observe($0) }

        #expect(
            events == [
                .foregroundProcessChanged(ForegroundProcess(name: "zsh")), nil,
                .foregroundProcessChanged(ForegroundProcess(name: "sleep")),
                .foregroundProcessChanged(ForegroundProcess(name: "zsh")),
            ])
    }

    @Test func trackerIgnoresUnknownName() {
        var tracker = ProcessNameTracker()

        let events = ["zsh", nil, "zsh"].map { tracker.observe($0) }

        #expect(events == [.foregroundProcessChanged(ForegroundProcess(name: "zsh")), nil, nil])
    }
}
