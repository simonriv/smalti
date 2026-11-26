import Darwin
import Foundation
import SmaltiCore

/// What `sysctl` tells about every process, readable by anyone: PID, parent, owner, state, terminal and start.
struct KernelProcess {
    let pid: Int32
    let parent: Int32
    let uid: uid_t
    let state: RunState
    let terminal: Int32?
    let name: String
    let startedAt: Date
}

enum KernelProcessTable {
    /// Every process now; empty if the kernel refuses (it does not without a sandbox).
    static func all() -> [KernelProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        // The table can grow between asking its size and reading it: a few tries with room to spare.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
            let capacity = size / MemoryLayout<kinfo_proc>.stride + 64
            var table = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            size = capacity * MemoryLayout<kinfo_proc>.stride
            if sysctl(&mib, 4, &table, &size, nil, 0) == 0 {
                return table.prefix(size / MemoryLayout<kinfo_proc>.stride).map(process)
            }
            guard errno == ENOMEM else { return [] }
        }
        return []
    }

    /// One process by PID; nil when it is gone.
    static func one(_ pid: Int32) -> KernelProcess? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return process(info)
    }

    private static let noDevice: Int32 = -1

    private static func process(_ info: kinfo_proc) -> KernelProcess {
        let start = info.kp_proc.p_un.__p_starttime
        let terminal = info.kp_eproc.e_tdev
        return KernelProcess(
            pid: info.kp_proc.p_pid, parent: info.kp_eproc.e_ppid, uid: info.kp_eproc.e_ucred.cr_uid,
            state: state(info.kp_proc.p_stat), terminal: terminal == noDevice ? nil : terminal,
            name: name(info.kp_proc.p_comm),
            startedAt: Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000))
    }

    private static func state(_ stat: CChar) -> RunState {
        switch Int32(stat) {
        case SRUN: .running
        case SSTOP: .stopped
        case SZOMB: .zombie
        default: .sleeping
        }
    }

    /// `p_comm` is a fixed C array of up to 16 characters plus NUL.
    private static func name(_ comm: some Any) -> String {
        withUnsafeBytes(of: comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
