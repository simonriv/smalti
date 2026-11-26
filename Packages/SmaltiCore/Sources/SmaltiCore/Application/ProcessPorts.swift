/// Why the system refused to act on a process.
public enum ProcessControlError: Error, Equatable, Sendable {
    /// The process ended, or its PID now belongs to another process.
    case gone
    /// It belongs to another user, or it is Smalti itself.
    case notYours
    /// The system said no; `code` is its `errno`.
    case refused(code: Int32)
}

/// Port: the processes on this Mac right now. Only the person's own are read in full.
public protocol RunningProcesses: Sendable {
    func current() async -> ProcessSample
}

/// Port: the ports processes listen on (TCP in LISTEN, unconnected UDP), only for the person's own processes.
public protocol ListeningPorts: Sendable {
    func current() async -> [ListeningSocket]
}

/// Port: acting on one of the person's processes. Each call carries the identity the person chose; the adapter
/// checks it still names the same process before it acts.
public protocol ProcessControl: Sendable {
    /// Asks it to end (SIGTERM).
    func stop(_ process: ProcessIdentity) async throws(ProcessControlError)
    /// Ends it without asking (SIGKILL).
    func forceStop(_ process: ProcessIdentity) async throws(ProcessControlError)
    /// Sets its nice value; only ever higher than now.
    func lowerPriority(_ process: ProcessIdentity, to nice: Int32) async throws(ProcessControlError)
}
