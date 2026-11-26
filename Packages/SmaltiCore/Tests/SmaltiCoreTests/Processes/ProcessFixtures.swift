import Foundation
import SmaltiCore

/// Builds process records for the tests: own, sleeping, no terminal, unless told otherwise.
enum ProcessFixtures {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let second: UInt64 = 1_000_000_000

    static func record(
        _ pid: Int32, parent: Int32 = 1, name: String = "proc", isOwn: Bool = true, terminal: Int32? = nil,
        executable: String? = nil, arguments: [String] = [], directory: String? = nil, run: RunState = .sleeping,
        cpuTime: UInt64? = 0, memory: UInt64 = 0, startedAt: Date = start, nice: Int32 = 0
    ) -> ProcessRecord {
        ProcessRecord(
            identity: ProcessIdentity(pid: pid, startedAt: startedAt), parent: parent, isOwn: isOwn, name: name,
            executable: executable, arguments: arguments, workingDirectory: directory, terminal: terminal,
            run: run, cpuTime: cpuTime, memory: memory, threads: 1, nice: nice)
    }

    static func sample(_ records: [ProcessRecord], at seconds: UInt64 = 10, hidden: Int = 0) -> ProcessSample {
        ProcessSample(records: records, takenAt: seconds * second, hiddenCount: hidden, memoryTotal: 16 << 30)
    }
}
