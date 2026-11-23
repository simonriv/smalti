import AppKit
import Carbon
import SmaltiCore

/// Applies `SecureEntry` to the system: secure keyboard entry is on while it is requested (the menu item or a
/// password prompt) and Smalti is the active app, so other apps keep their global shortcuts while the user is
/// elsewhere. Each change is balanced: the system counts per process.
@MainActor
final class SecureInput {
    private(set) var entry = SecureEntry()
    private var observers: [NSObjectProtocol] = []

    init() {
        entry = entry.activated(NSApp?.isActive ?? false)
        let center = NotificationCenter.default
        for (name, isActive) in [
            (NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false),
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.change { $0.activated(isActive) } }
                })
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func toggle() { change { $0.toggledByUser() } }

    func prompt(in pane: PaneID, isAsking: Bool) { change { $0.prompt(in: pane, isAsking: isAsking) } }

    /// Panes that closed while their prompt asked stop asking.
    func keep(panes: Set<PaneID>) { change { $0.keeping(panes: panes) } }

    /// Quitting leaves the system as it found it.
    func releaseAll() { change { $0.activated(false) } }

    private func change(_ transform: (SecureEntry) -> SecureEntry) {
        let wasApplied = entry.isApplied
        entry = transform(entry)
        guard wasApplied != entry.isApplied else { return }
        _ = entry.isApplied ? EnableSecureEventInput() : DisableSecureEventInput()
    }
}
