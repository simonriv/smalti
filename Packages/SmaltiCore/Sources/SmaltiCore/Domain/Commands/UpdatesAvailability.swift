/// F7.6: whether this build can update itself, and whether it checks on its own.
public enum UpdatesAvailability: Equatable, Sendable {
    case unavailable
    case available(isAutomatic: Bool)
}
