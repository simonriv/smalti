import Darwin
import Foundation

/// What only the owner of a process may read: arguments, directory, executable, CPU, memory, threads and nice.
enum ProcessDetails {
    struct Task {
        let cpuTime: UInt64
        let threads: Int
    }

    /// User plus system CPU time in nanoseconds and the thread count; nil when the process is gone or not ours.
    static func task(_ pid: Int32, timebase: mach_timebase_info_data_t) -> Task? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        // On Apple Silicon these are Mach absolute time units, not nanoseconds.
        let ticks = info.pti_total_user + info.pti_total_system
        let nanoseconds = ticks.multipliedReportingOverflow(by: UInt64(timebase.numer))
        let cpu = nanoseconds.overflow ? UInt64.max : nanoseconds.partialValue / UInt64(max(timebase.denom, 1))
        return Task(cpuTime: cpu, threads: Int(info.pti_threadnum))
    }

    /// Physical footprint: Activity Monitor's "Memory".
    static func footprint(_ pid: Int32) -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            // proc_pid_rusage writes a rusage_info_v4 through an untyped pointer to it.
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? usage.ri_phys_footprint : nil
    }

    static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    static func executable(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The nice value; nil when it cannot be read (`getpriority` returns -1 both for errors and for nice -1).
    static func nice(_ pid: Int32) -> Int32? {
        errno = 0
        let value = getpriority(PRIO_PROCESS, id_t(pid))
        return errno == 0 ? value : nil
    }

    /// `KERN_PROCARGS2`: `argc` (Int32), the executable path, NUL padding, then `argc` NUL-terminated arguments.
    static func arguments(_ pid: Int32) -> [String]? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseArguments(Array(buffer.prefix(size)))
    }

    static func parseArguments(_ record: [UInt8]) -> [String]? {
        let countSize = MemoryLayout<Int32>.size
        guard record.count >= countSize else { return nil }
        let argc = record.prefix(countSize).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        var position = countSize
        while position < record.count, record[position] != 0 { position += 1 }
        while position < record.count, record[position] == 0 { position += 1 }
        var arguments: [String] = []
        while arguments.count < argc, position < record.count {
            let end = record[position...].firstIndex(of: 0) ?? record.count
            arguments.append(String(decoding: record[position..<end], as: UTF8.self))
            position = end + 1
        }
        return arguments.count == argc ? arguments : nil
    }
}
