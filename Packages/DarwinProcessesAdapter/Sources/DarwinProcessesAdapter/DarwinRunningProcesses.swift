import Darwin
import Dispatch
import Foundation
import SmaltiCore

/// `RunningProcesses` from `sysctl` and libproc, without privileges or child processes. Other users' processes
/// carry only what the kernel tells anyone (PID, parent, terminal, name) and count as hidden (spec F8, fact 2).
public struct DarwinRunningProcesses: RunningProcesses {
    private let uid = getuid()
    private let memoryTotal: UInt64 = {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        return sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0 ? value : 0
    }()
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init() {}

    public func current() async -> ProcessSample {
        let kernel = KernelProcessTable.all()
        let records = kernel.map { $0.uid == uid ? ownRecord($0) : otherRecord($0) }
        return ProcessSample(
            records: records, takenAt: DispatchTime.now().uptimeNanoseconds,
            hiddenCount: records.filter { !$0.isOwn }.count, memoryTotal: memoryTotal)
    }

    private func ownRecord(_ process: KernelProcess) -> ProcessRecord {
        let task = ProcessDetails.task(process.pid, timebase: timebase)
        return ProcessRecord(
            identity: ProcessIdentity(pid: process.pid, startedAt: process.startedAt), parent: process.parent,
            isOwn: true, name: process.name, executable: ProcessDetails.executable(process.pid),
            arguments: ProcessDetails.arguments(process.pid) ?? [],
            workingDirectory: ProcessDetails.workingDirectory(process.pid), terminal: process.terminal,
            run: process.state, cpuTime: task?.cpuTime ?? 0, memory: ProcessDetails.footprint(process.pid) ?? 0,
            threads: task?.threads ?? 0, nice: ProcessDetails.nice(process.pid) ?? 0)
    }

    private func otherRecord(_ process: KernelProcess) -> ProcessRecord {
        ProcessRecord(
            identity: ProcessIdentity(pid: process.pid, startedAt: process.startedAt), parent: process.parent,
            isOwn: false, name: process.name, executable: nil, arguments: [], workingDirectory: nil,
            terminal: process.terminal, run: process.state, cpuTime: 0, memory: 0, threads: 0, nice: 0)
    }
}
