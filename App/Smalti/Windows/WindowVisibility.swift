import AppKit

/// Whether a window is the one the user looks at: the app is active and it is the key window, not minimized. A
/// controller asks it to decide if an agent's state change needs a notification (F4.5: per window, not per app).
@MainActor
final class WindowVisibility {
    weak var window: NSWindow?

    var isSeen: Bool {
        guard NSApp.isActive, let window else { return false }
        return window.isKeyWindow && !window.isMiniaturized
    }
}
