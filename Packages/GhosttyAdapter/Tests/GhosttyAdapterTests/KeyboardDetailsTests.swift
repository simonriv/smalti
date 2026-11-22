import AppKit
import GhosttyKit
import Testing

@testable import GhosttyAdapter

/// Review minor findings on the keyboard path, matching ghostty v1.4.0 SurfaceView_AppKit.
@MainActor
@Suite("Keyboard details")
struct KeyboardDetailsTests {
    private enum KeyCode {
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
        static let a: UInt16 = 0
        static let leftShift: UInt16 = 0x38
        static let rightShift: UInt16 = 0x3C
    }

    @Test(arguments: [KeyCode.rightArrow, KeyCode.downArrow, KeyCode.upArrow])
    func arrowAfterCommittedDeadKeyIsReplayed(_ keyCode: UInt16) {
        #expect(GhosttyInput.shouldReplayAfterCommittingPreedit(keyCode: keyCode, modifiers: []))
    }

    @Test func plainLeftArrowIsNotReplayed() {
        #expect(!GhosttyInput.shouldReplayAfterCommittingPreedit(keyCode: KeyCode.leftArrow, modifiers: []))
    }

    @Test func modifiedLeftArrowIsReplayed() {
        #expect(GhosttyInput.shouldReplayAfterCommittingPreedit(keyCode: KeyCode.leftArrow, modifiers: [.shift]))
    }

    @Test func letterIsNotReplayed() {
        #expect(!GhosttyInput.shouldReplayAfterCommittingPreedit(keyCode: KeyCode.a, modifiers: []))
    }

    @Test func keyThatSwitchedTheInputSourceIsDropped() {
        #expect(
            GhosttyInput.isInputSourceSwitch(
                hadMarkedText: false, layoutBefore: "com.apple.keylayout.LatinAmerican",
                layoutAfter: "com.apple.keylayout.US"))
    }

    @Test func sameInputSourceKeepsTheKey() {
        #expect(!GhosttyInput.isInputSourceSwitch(hadMarkedText: false, layoutBefore: "A", layoutAfter: "A"))
    }

    @Test func layoutChangeWhileComposingKeepsTheKey() {
        #expect(!GhosttyInput.isInputSourceSwitch(hadMarkedText: true, layoutBefore: "A", layoutAfter: "B"))
    }

    @Test func pressingLeftShiftIsAPress() {
        let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | UInt(NX_DEVICELSHIFTKEYMASK))
        #expect(GhosttyInput.modifierAction(keyCode: KeyCode.leftShift, flags: flags) == GHOSTTY_ACTION_PRESS)
    }

    @Test func releasingRightShiftWhileLeftIsHeldIsARelease() {
        // Shift is still down (left side), but the right side is not: the right key went up.
        let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | UInt(NX_DEVICELSHIFTKEYMASK))
        #expect(GhosttyInput.modifierAction(keyCode: KeyCode.rightShift, flags: flags) == GHOSTTY_ACTION_RELEASE)
    }

    @Test func releasingTheLastShiftIsARelease() {
        #expect(GhosttyInput.modifierAction(keyCode: KeyCode.leftShift, flags: []) == GHOSTTY_ACTION_RELEASE)
    }

    @Test func nonModifierKeyHasNoModifierAction() {
        #expect(GhosttyInput.modifierAction(keyCode: KeyCode.a, flags: []) == nil)
    }
}
