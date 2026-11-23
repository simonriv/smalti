import Carbon

/// "Entrada de teclado segura": while on, other apps cannot read Smalti's keystrokes. The menu item toggles it; a
/// password prompt asks for it too (libghostty's `SECURE_INPUT`, F4.5). Each request is balanced: the system keeps a
/// count per process.
@MainActor
final class SecureInput {
    private(set) var isOnByUser = false
    private var promptsAsking = 0

    var isOn: Bool { isOnByUser || promptsAsking > 0 }

    func toggle() {
        set(user: !isOnByUser)
    }

    /// A password prompt started or ended in some pane.
    func promptRequested(_ isOn: Bool) {
        let was = self.isOn
        promptsAsking = max(0, promptsAsking + (isOn ? 1 : -1))
        apply(from: was)
    }

    /// Quitting leaves the system's count as it found it.
    func releaseAll() {
        let was = isOn
        isOnByUser = false
        promptsAsking = 0
        apply(from: was)
    }

    private func set(user isOn: Bool) {
        let was = self.isOn
        isOnByUser = isOn
        apply(from: was)
    }

    private func apply(from was: Bool) {
        guard was != isOn else { return }
        _ = isOn ? EnableSecureEventInput() : DisableSecureEventInput()
    }
}
