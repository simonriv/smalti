import Darwin
import Foundation

/// When a process started (F6: a harness's session is the one created after its process started).
enum ProcessStart {
    /// Nil when `pid` is not a process id, or the process is gone or not ours to inspect.
    static func of(pid: pid_t) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
    }
}
