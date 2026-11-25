/// Port (F7.6): the app's updater, driven by the user. The updater shows its own windows and verifies every update's
/// EdDSA signature; the domain only asks it to check and remembers nothing.
@MainActor
public protocol AppUpdates: AnyObject {
    /// Checks the feed now and shows the result (a new version, or that this one is the newest).
    func checkNow()
    /// Whether the updater checks on its own every day.
    var isAutomatic: Bool { get }
    func setAutomatic(_ isOn: Bool)
}

/// «Buscar actualizaciones…».
@MainActor
public struct CheckForUpdates {
    private let updates: any AppUpdates

    public init(updates: any AppUpdates) {
        self.updates = updates
    }

    public func execute() { updates.checkNow() }
}

/// «Desactivar/Activar actualizaciones automáticas»: flips the automatic check and says what it is now.
@MainActor
public struct SetAutomaticUpdates {
    private let updates: any AppUpdates

    public init(updates: any AppUpdates) {
        self.updates = updates
    }

    public func toggle() -> String {
        let isOn = !updates.isAutomatic
        updates.setAutomatic(isOn)
        return isOn ? "Actualizaciones automáticas activadas" : "Actualizaciones automáticas desactivadas"
    }
}

extension UpdatesAvailability {
    /// What the palette and the menus offer for `updates` (nil: a build without an updater, like Smalti Dev).
    @MainActor
    public init(_ updates: (any AppUpdates)?) {
        self = updates.map { .available(isAutomatic: $0.isAutomatic) } ?? .unavailable
    }
}
