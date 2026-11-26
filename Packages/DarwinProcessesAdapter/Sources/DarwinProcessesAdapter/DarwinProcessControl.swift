import Darwin
import Foundation
import SmaltiCore

/// `ProcessControl` with POSIX signals and `setpriority`. Before acting it reads the process again: it must still
/// be the chosen one (same start), belong to this user and not be this process. The domain's `StopPolicy` decides
/// what is offered; this is the last check before the kernel (spec F8, C2).
public struct DarwinProcessControl: ProcessControl {
    private let uid = getuid()
    private let ownPID = getpid()

    public init() {}

    public func stop(_ process: ProcessIdentity) async throws(ProcessControlError) {
        try check(process)
        try signal(process.pid, SIGTERM)
    }

    public func forceStop(_ process: ProcessIdentity) async throws(ProcessControlError) {
        try check(process)
        try signal(process.pid, SIGKILL)
    }

    public func lowerPriority(_ process: ProcessIdentity, to nice: Int32) async throws(ProcessControlError) {
        try check(process)
        errno = 0
        let current = getpriority(PRIO_PROCESS, id_t(process.pid))
        if errno != 0 { throw failure(errno) }
        // Only ever down in priority: without privileges the kernel refuses the rest anyway.
        guard nice >= current else { throw .refused(code: EACCES) }
        guard setpriority(PRIO_PROCESS, id_t(process.pid), nice) == 0 else { throw failure(errno) }
    }

    private func check(_ process: ProcessIdentity) throws(ProcessControlError) {
        guard let now = KernelProcessTable.one(process.pid), now.startedAt == process.startedAt else { throw .gone }
        guard now.uid == uid, process.pid != ownPID else { throw .notYours }
    }

    private func signal(_ pid: Int32, _ number: Int32) throws(ProcessControlError) {
        guard kill(pid, number) == 0 else { throw failure(errno) }
    }

    private func failure(_ code: Int32) -> ProcessControlError {
        switch code {
        case ESRCH: .gone
        case EPERM: .notYours
        default: .refused(code: code)
        }
    }
}
