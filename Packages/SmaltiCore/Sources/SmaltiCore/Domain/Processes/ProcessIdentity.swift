import Foundation

/// A process as the kernel told it apart: its PID plus when it started, so a reused PID is never taken for the
/// process that was chosen (spec F8, "Identidad").
public struct ProcessIdentity: Hashable, Sendable {
    public let pid: Int32
    public let startedAt: Date

    public init(pid: Int32, startedAt: Date) {
        self.pid = pid
        self.startedAt = startedAt
    }
}
