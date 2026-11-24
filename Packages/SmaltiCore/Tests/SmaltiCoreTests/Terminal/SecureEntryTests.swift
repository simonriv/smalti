import SmaltiCore
import Testing

/// Block 4 review: secure keyboard entry, as the menu item and the password prompts ask for it, applied only while
/// Smalti is the active app.
@Suite("SecureEntry")
struct SecureEntryTests {
    private let pane = PaneID()
    private let other = PaneID()

    @Test func offByDefault() {
        let entry = SecureEntry()

        #expect(!entry.isRequested)
        #expect(!entry.isApplied)
    }

    @Test func aPromptRequestsItWhileTheAppIsActive() {
        let entry = SecureEntry().activated(true).prompt(in: pane, isAsking: true)

        #expect(entry.isRequested)
        #expect(entry.isApplied)
        #expect(!entry.isOnByUser)
    }

    @Test func inTheBackgroundItIsRequestedButNotApplied() {
        let entry = SecureEntry().activated(true).prompt(in: pane, isAsking: true).activated(false)

        #expect(entry.isRequested)
        #expect(!entry.isApplied)
    }

    @Test func aClosedPaneStopsAsking() {
        let entry = SecureEntry().activated(true).prompt(in: pane, isAsking: true).keeping(panes: [other])

        #expect(!entry.isRequested)
    }

    @Test func twoPanesAskUntilBothStop() {
        let both = SecureEntry().activated(true).prompt(in: pane, isAsking: true).prompt(in: other, isAsking: true)

        #expect(both.prompt(in: pane, isAsking: false).isRequested)
        #expect(!both.prompt(in: pane, isAsking: false).prompt(in: other, isAsking: false).isRequested)
    }

    @Test func theUserToggleIsItsOwn() {
        let asked = SecureEntry().activated(true).prompt(in: pane, isAsking: true)

        let toggled = asked.toggledByUser()

        #expect(toggled.isOnByUser)
        #expect(!toggled.toggledByUser().isOnByUser)
        #expect(toggled.toggledByUser().isRequested)
    }

    /// Mutation (F4.5): until AppKit says Smalti is active, nothing is applied to the system.
    @Test func notAppliedBeforeTheAppIsActivated() {
        #expect(!SecureEntry().toggledByUser().isApplied)
    }
}
