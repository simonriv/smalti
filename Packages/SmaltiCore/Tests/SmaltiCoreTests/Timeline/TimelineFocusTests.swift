import Foundation
import SmaltiCore
import Testing

/// Review 2 (C2): what the timeline does when the focused pane changes, or only its look does.
@Suite("TimelineFocus")
struct TimelineFocusTests {
    private func focus(_ resolution: TimelineTarget.Resolution, root: String = "/w", pane: String = "acme · 1")
        -> TimelineFocus
    {
        TimelineFocus(resolution: resolution, root: root, pane: pane)
    }

    @Test func aFirstFocusReads() {
        #expect(TimelineFocus.change(from: nil, to: focus(.noAgent), isPinned: false) == .read)
    }

    @Test func theSameSessionOnlyRepaints() {
        let before = focus(.session(.claude, "c1"))

        #expect(TimelineFocus.change(from: before, to: before, isPinned: false) == .repaint)
    }

    @Test(arguments: [
        TimelineFocus(resolution: .session(.claude, "c2"), root: "/w", pane: "acme · 1"),
        TimelineFocus(resolution: .session(.claude, "c1"), root: "/x", pane: "acme · 1"),
        TimelineFocus(resolution: .session(.claude, "c1"), root: "/w", pane: "acme · 2"),
    ])
    func anotherSessionRootOrPaneReads(next: TimelineFocus) {
        #expect(TimelineFocus.change(from: focus(.session(.claude, "c1")), to: next, isPinned: false) == .read)
    }

    @Test func aPinnedSessionStaysWhileThePaneIsTheSame() {
        let before = focus(.session(.claude, "c1"))

        #expect(TimelineFocus.change(from: before, to: focus(.noAgent), isPinned: true) == .repaint)
        #expect(TimelineFocus.change(from: before, to: focus(.noAgent, pane: "acme · 2"), isPinned: true) == .read)
    }
}
