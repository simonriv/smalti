import Foundation

/// What the kernel says a process is doing.
public enum RunState: Equatable, Sendable {
    case running
    case sleeping
    case stopped
    case zombie
}

/// One process as read in a sample. Only the person's own processes are read in full; the others carry just what
/// anyone may know (PID, parent, terminal, name) so the panes can still be told apart.
public struct ProcessRecord: Equatable, Sendable {
    public let identity: ProcessIdentity
    public let parent: Int32
    public let isOwn: Bool
    /// The kernel's short name (`p_comm`).
    public let name: String
    /// The executable's full path; nil when it cannot be read.
    public let executable: String?
    public let arguments: [String]
    public let workingDirectory: String?
    /// The controlling terminal's device; nil without one.
    public let terminal: Int32?
    public let run: RunState
    /// User plus system CPU time, in nanoseconds.
    public let cpuTime: UInt64
    /// Physical footprint, in bytes (Activity Monitor's "Memory").
    public let memory: UInt64
    public let threads: Int
    public let nice: Int32

    public init(
        identity: ProcessIdentity, parent: Int32, isOwn: Bool, name: String, executable: String?,
        arguments: [String], workingDirectory: String?, terminal: Int32?, run: RunState, cpuTime: UInt64,
        memory: UInt64, threads: Int, nice: Int32
    ) {
        self.identity = identity
        self.parent = parent
        self.isOwn = isOwn
        self.name = name
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.terminal = terminal
        self.run = run
        self.cpuTime = cpuTime
        self.memory = memory
        self.threads = threads
        self.nice = nice
    }

    public var pid: Int32 { identity.pid }
}
