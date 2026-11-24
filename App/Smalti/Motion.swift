import AppKit

/// "Reducir movimiento" (spec F5 C15). `-SmaltiReduceMotion YES|NO` stands in for the system setting in UI tests.
enum Motion {
    static let reduceMotionKey = "SmaltiReduceMotion"

    @MainActor
    static var isReduced: Bool {
        guard UserDefaults.standard.object(forKey: reduceMotionKey) != nil else {
            return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        return UserDefaults.standard.bool(forKey: reduceMotionKey)
    }
}
