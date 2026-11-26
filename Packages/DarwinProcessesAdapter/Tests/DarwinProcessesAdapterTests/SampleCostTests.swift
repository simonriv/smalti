import DarwinProcessesAdapter
import Foundation
import Testing

/// C10 of F8: reading every process and every listener costs under 50 ms (p95 of 20).
@Suite("Sample cost")
struct SampleCostTests {
    @Test func processesAndPortsUnderFiftyMilliseconds() async {
        let processes = DarwinRunningProcesses()
        let ports = DarwinListeningPorts()
        var durations: [Duration] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            _ = await processes.current()
            _ = await ports.current()
            durations.append(ContinuousClock.now - start)
        }
        let p95 = durations.sorted()[18]

        print("[sample cost] p95 \(p95), max \(durations.max() ?? .zero)")
        #expect(p95 < .milliseconds(50))
    }
}
