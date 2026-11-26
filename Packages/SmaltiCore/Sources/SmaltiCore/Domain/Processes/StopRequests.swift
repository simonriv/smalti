/// Where a request to stop a process stands.
public enum StopPhase: Equatable, Sendable {
    /// SIGTERM sent at this monotonic instant (ns); waiting for it to end.
    case requested(at: UInt64)
    /// It outlived the grace period.
    case unresponsive
    /// The person asked to force it; waiting for them to confirm.
    case confirming
}
