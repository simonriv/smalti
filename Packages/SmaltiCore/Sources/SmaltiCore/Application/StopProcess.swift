/// What pressing "Stop" (or confirming to force) did.
public enum StopOutcome: Equatable, Sendable {
    case requested
    /// Still within the grace period, or nothing to confirm.
    case waiting
    case confirming
    case forced
    case protected(ProtectionReason)
    case failed(ProcessControlError)
}

/// Stops one of the person's processes: SIGTERM first; if it outlives the grace period, the next press asks to
/// confirm and only the confirmation sends SIGKILL (spec F8, "Detener").
@MainActor
public final class StopProcess {
    private let control: any ProcessControl
    private let grace: UInt64
    public private(set) var requests = StopRequests()

    /// `grace` in the same unit as the `now` values (nanoseconds of the monotonic clock in the app).
    public init(control: any ProcessControl, grace: UInt64) {
        self.control = control
        self.grace = grace
    }

    public func press(_ row: ProcessRow, now: UInt64) async -> StopOutcome {
        if case .protected(let reason) = row.verdict { return .protected(reason) }
        switch requests.phase(of: row.identity) {
        case .requested: return .waiting
        case .confirming: return .confirming
        case .unresponsive:
            _ = requests.askToForce(row.identity)
            return .confirming
        case nil: return await requestStop(row.identity, now: now)
        }
    }

    public func confirm(_ process: ProcessIdentity) async -> StopOutcome {
        guard requests.phase(of: process) == .confirming else { return .waiting }
        do {
            try await control.forceStop(process)
            requests.forget(process)
            return .forced
        } catch {
            if error == .gone { requests.forget(process) } else { requests.cancel(process) }
            return .failed(error)
        }
    }

    public func cancel(_ process: ProcessIdentity) {
        requests.cancel(process)
    }

    /// After each refresh: forgets what ended and marks what outlived the grace period.
    public func tick(alive: Set<ProcessIdentity>, now: UInt64) {
        requests.tick(alive: alive, now: now, grace: grace)
    }

    private func requestStop(_ process: ProcessIdentity, now: UInt64) async -> StopOutcome {
        do {
            try await control.stop(process)
            requests.request(process, at: now)
            return .requested
        } catch {
            return .failed(error)
        }
    }
}
