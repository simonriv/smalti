/// Decides whether a notice may be shown. The current permission is checked every time, so one granted later in
/// System Settings works without restarting; while macOS still has to ask, every notice waits for the one prompt; a
/// denial is reported once.
@MainActor
final class AuthorizationGate {
    /// nil while macOS has not asked yet.
    private let current: @MainActor () async -> Bool?
    private let request: @MainActor () async -> Bool
    private let onDenied: @MainActor () -> Void
    private var pendingRequest: Task<Bool, Never>?
    private var hasReportedDenial = false

    init(
        current: @escaping @MainActor () async -> Bool?, request: @escaping @MainActor () async -> Bool,
        onDenied: @escaping @MainActor () -> Void
    ) {
        self.current = current
        self.request = request
        self.onDenied = onDenied
    }

    func isAllowed() async -> Bool {
        let allowed: Bool
        if let decided = await current() {
            allowed = decided
        } else {
            let asking = pendingRequest ?? Task { await request() }
            pendingRequest = asking
            allowed = await asking.value
        }
        if !allowed, !hasReportedDenial {
            hasReportedDenial = true
            onDenied()
        }
        return allowed
    }
}
