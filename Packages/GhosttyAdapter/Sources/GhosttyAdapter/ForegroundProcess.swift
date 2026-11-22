import Darwin

/// Names the process in a terminal's foreground (R3). libghostty gives the foreground process group
/// (`tcgetpgrp`); its leader's id is the group id, so `proc_name` on it names the running program.
enum ForegroundProcess {
    /// `proc_name` copies at most `2 * MAXCOMLEN` bytes; one more keeps room for the terminator.
    private static let nameCapacity = 2 * Int(MAXCOMLEN) + 1

    /// Nil when `pid` is not a process id or the process is gone or not ours to inspect.
    static func name(ofProcessGroup pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: nameCapacity)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
