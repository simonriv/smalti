import Darwin

/// Reads a process's arguments (`sysctl` `KERN_PROCARGS2`), to relaunch the program a pane was running.
enum ProcessArguments {
    /// Nil when the process is gone, is not ours to inspect, or its record cannot be parsed.
    static func of(pid: pid_t) -> [String]? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buffer.prefix(size)))
    }

    /// Layout: `argc` (Int32), the executable path, NUL padding, then `argc` NUL-terminated arguments.
    private static func parse(_ record: [UInt8]) -> [String]? {
        let countSize = MemoryLayout<Int32>.size
        let argc = record.prefix(countSize).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        var position = countSize
        while position < record.count, record[position] != 0 { position += 1 }  // executable path
        while position < record.count, record[position] == 0 { position += 1 }  // padding
        var arguments: [String] = []
        while arguments.count < argc, position < record.count {
            let end = record[position...].firstIndex(of: 0) ?? record.count
            arguments.append(String(decoding: record[position..<end], as: UTF8.self))
            position = end + 1
        }
        return arguments.count == argc ? arguments : nil
    }
}
