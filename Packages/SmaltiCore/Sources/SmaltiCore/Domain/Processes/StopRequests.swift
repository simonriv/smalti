/// Where a request to stop a process stands.
public enum StopPhase: Equatable, Sendable {
    /// SIGTERM sent at this monotonic instant (ns); waiting for it to end.
    case requested(at: UInt64)
    /// It outlived the grace period.
    case unresponsive
    /// The person asked to force it; waiting for them to confirm.
    case confirming
}

/// Pending requests to stop processes. SIGKILL is only ever reachable from `.confirming`, which only an
/// unresponsive process can enter (spec F8, C3).
public struct StopRequests: Equatable, Sendable {
    public private(set) var phases: [ProcessIdentity: StopPhase] = [:]

    public init() {}

    public func phase(of process: ProcessIdentity) -> StopPhase? {
        phases[process]
    }

    public mutating func request(_ process: ProcessIdentity, at now: UInt64) {
        phases[process] = .requested(at: now)
    }

    /// Forgets what ended; what outlived `grace` since its request becomes unresponsive.
    public mutating func tick(alive: Set<ProcessIdentity>, now: UInt64, grace: UInt64) {
        for (process, phase) in phases {
            guard alive.contains(process) else {
                phases[process] = nil
                continue
            }
            if case .requested(let at) = phase, now >= at, now - at >= grace { phases[process] = .unresponsive }
        }
    }

    /// Moves an unresponsive process to confirming; false (and no change) otherwise.
    public mutating func askToForce(_ process: ProcessIdentity) -> Bool {
        guard phases[process] == .unresponsive else { return false }
        phases[process] = .confirming
        return true
    }

    public mutating func cancel(_ process: ProcessIdentity) {
        guard phases[process] == .confirming else { return }
        phases[process] = .unresponsive
    }

    /// Every confirmation is dropped: what was confirming is unresponsive again (closing the view).
    public mutating func cancelConfirmations() {
        for (process, phase) in phases where phase == .confirming { phases[process] = .unresponsive }
    }

    /// Back to unresponsive after forcing it failed for a reason other than it having ended.
    mutating func restoreUnresponsive(_ process: ProcessIdentity) {
        phases[process] = .unresponsive
    }

    public mutating func forget(_ process: ProcessIdentity) {
        phases[process] = nil
    }
}
