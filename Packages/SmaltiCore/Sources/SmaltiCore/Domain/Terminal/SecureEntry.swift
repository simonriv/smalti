/// Secure keyboard entry (F4.5): asked for by the menu item and by password prompts, pane by pane, and applied to
/// the system only while Smalti is the active app (while on, other apps lose their global shortcuts).
public struct SecureEntry: Equatable, Sendable {
    public private(set) var isOnByUser = false
    private var askingPanes: Set<PaneID> = []
    private var isAppActive = false

    public init() {}

    /// Something wants it: the user, or a password prompt in some pane. The status bar shows this.
    public var isRequested: Bool { isOnByUser || !askingPanes.isEmpty }

    /// What the system should have now.
    public var isApplied: Bool { isRequested && isAppActive }

    public func toggledByUser() -> SecureEntry {
        var updated = self
        updated.isOnByUser.toggle()
        return updated
    }

    public func prompt(in pane: PaneID, isAsking: Bool) -> SecureEntry {
        var updated = self
        if isAsking { updated.askingPanes.insert(pane) } else { updated.askingPanes.remove(pane) }
        return updated
    }

    /// A pane that closed while its prompt asked never says it stopped: only the panes that remain keep asking.
    public func keeping(panes: Set<PaneID>) -> SecureEntry {
        var updated = self
        updated.askingPanes.formIntersection(panes)
        return updated
    }

    public func activated(_ isActive: Bool) -> SecureEntry {
        var updated = self
        updated.isAppActive = isActive
        return updated
    }
}
