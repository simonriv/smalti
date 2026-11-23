import Darwin
import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@testable import DarwinMetricsAdapter

@Suite("DarwinSystemMetrics")
struct DarwinSystemMetricsTests {
    @Test func cpuUsageFromTickDeltas() {
        let previous = CPUTicks(busy: 100, total: 1_000)
        let current = CPUTicks(busy: 410, total: 2_000)

        #expect(CPUTicks.usage(previous: previous, current: current) == 31)
    }

    @Test func noElapsedTicksIsUnavailable() {
        let ticks = CPUTicks(busy: 5, total: 10)

        #expect(CPUTicks.usage(previous: ticks, current: ticks) == nil)
    }

    @Test func usedMemoryAddsActiveWiredCompressed() {
        let pages = MemoryPages(active: 100, wired: 50, compressed: 25)

        #expect(MemoryReader.used(pages, pageSize: 16_384) == 175 * 16_384)
    }

    static let levels: [(Int32, MemoryPressure)] = [(1, .normal), (2, .media), (4, .alta)]

    @Test(arguments: levels)
    func pressureLevelsMapToNormalMediaAlta(level: Int32, pressure: MemoryPressure) {
        #expect(MemoryReader.pressure(level: level) == .value(pressure))
    }

    @Test func unknownPressureLevelIsUnavailable() {
        #expect(MemoryReader.pressure(level: 3) == .unavailable)
    }

    @Test func productNameTrimsTrailingNullAndKeepsTheChip() {
        let data = Data("MacBook Air (13-inch, M4, 2025)\0".utf8)

        #expect(MachineName.display(productName: data, chip: "Apple M4") == "MacBook Air M4")
    }

    @Test func missingProductNameFallsBackToTheChip() {
        #expect(MachineName.display(productName: nil, chip: "Apple M4") == "Apple M4")
    }

    @Test func productNameWithoutParenthesesIsKept() {
        #expect(MachineName.display(productName: Data("Mac mini".utf8), chip: "Apple M4") == "Mac mini M4")
    }

    @MainActor
    @Test func firstCpuSampleIsUnavailable() {
        #expect(DarwinSystemMetrics().sample(agentProcesses: []).cpu == .unavailable)
    }

    @MainActor
    @Test func realSampleIsInRange() throws {
        let metrics = DarwinSystemMetrics()
        _ = metrics.sample(agentProcesses: [])
        Thread.sleep(forTimeInterval: 0.2)

        let sample = metrics.sample(agentProcesses: [])

        let cpu = try #require(sample.cpu.value)
        #expect((0...100).contains(cpu))
        if let gpu = sample.gpu.value { #expect((0...100).contains(gpu)) }
        let used = try #require(sample.memoryUsed.value)
        #expect(used > 0 && used <= sample.memoryTotal)
        #expect(!sample.machineName.isEmpty)
        #expect(sample.pressure != .unavailable)
    }

    @MainActor
    @Test func ownProcessFootprintIsPositive() throws {
        let sample = DarwinSystemMetrics().sample(agentProcesses: [getpid(), 999_999])

        #expect(try #require(sample.agentsMemory.value) > 0)
    }

    @MainActor
    @Test func adapterHonoursTheContract() {
        let metrics = DarwinSystemMetrics()
        _ = metrics.sample(agentProcesses: [])

        SystemMetricsContract.verify(metrics, agentProcesses: [getpid()])
    }
}
