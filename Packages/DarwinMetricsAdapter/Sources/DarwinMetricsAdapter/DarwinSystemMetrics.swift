import Darwin
import Foundation
import IOKit
import SmaltiCore

/// `SystemMetrics` from the kernel and the I/O Registry, without privileges or child processes. A reading the
/// system does not give comes back `.unavailable`, never 0.
@MainActor
public final class DarwinSystemMetrics: SystemMetrics {
    /// Each `mach_host_self()` call adds a reference to the port; it is asked for once and kept.
    private let host = mach_host_self()
    private var previousTicks: CPUTicks?
    private lazy var machineName = DarwinSystemMetrics.readMachineName()
    private let memoryTotal = DarwinSystemMetrics.sysctlUInt64("hw.memsize") ?? 0

    public init() {}

    public func sample(agentProcesses: [Int32]) -> SystemSample {
        let ticks = Self.cpuTicks(host: host)
        var cpu: Double?
        if let previous = previousTicks, let ticks { cpu = CPUTicks.usage(previous: previous, current: ticks) }
        previousTicks = ticks ?? previousTicks
        return SystemSample(
            cpu: Self.reading(cpu), gpu: Self.reading(Self.gpuUtilization()),
            memoryUsed: Self.reading(Self.memoryUsed(host: host)),
            memoryTotal: memoryTotal, agentsMemory: Self.reading(Self.footprint(of: agentProcesses)),
            pressure: Self.sysctlInt32("kern.memorystatus_vm_pressure_level").map(MemoryReader.pressure)
                ?? .unavailable,
            machineName: machineName)
    }

    private static func reading<Value: Equatable & Sendable>(_ value: Value?) -> Reading<Value> {
        value.map { .value($0) } ?? .unavailable
    }

    // MARK: - CPU

    private static func cpuTicks(host: host_t) -> CPUTicks? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
            let info
        else { return nil }
        defer {
            // The kernel allocated `info` in our address space; it is ours to give back, once, here.
            vm_deallocate(
                mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(count) {
            let user = UInt64(info[core * states + Int(CPU_STATE_USER)])
            let system = UInt64(info[core * states + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[core * states + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[core * states + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return CPUTicks(busy: busy, total: total)
    }

    // MARK: - GPU

    private static func gpuUtilization() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(
            service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)
        let statistics = property?.takeRetainedValue() as? [String: Any]
        return (statistics?["Device Utilization %"] as? NSNumber)?.doubleValue
    }

    // MARK: - Memory

    private static func memoryUsed(host: host_t) -> UInt64? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            // vm_statistics64 is a plain C struct of integer_t-sized fields; the kernel fills `count` of them.
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = MemoryPages(
            active: UInt64(statistics.active_count), wired: UInt64(statistics.wire_count),
            compressed: UInt64(statistics.compressor_page_count))
        return MemoryReader.used(pages, pageSize: UInt64(getpagesize()))
    }

    /// The physical footprint of the given processes; those that are gone or not ours are left out.
    private static func footprint(of pids: [Int32]) -> UInt64? {
        let readings = pids.compactMap { pid -> UInt64? in
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                // proc_pid_rusage writes a rusage_info_v4 through an untyped pointer to it.
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            return result == 0 ? usage.ri_phys_footprint : nil
        }
        return pids.isEmpty || !readings.isEmpty ? readings.reduce(0, +) : nil
    }

    // MARK: - Machine

    private static func readMachineName() -> String {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Mac"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return chip }
        defer { IOObjectRelease(entry) }
        let property = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)
        return MachineName.display(productName: property?.takeRetainedValue() as? Data, chip: chip)
    }

    // MARK: - sysctl

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    private static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
