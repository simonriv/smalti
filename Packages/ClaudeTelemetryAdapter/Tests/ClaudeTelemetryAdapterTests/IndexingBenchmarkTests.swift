import Darwin
import Foundation
import SmaltiCore
import Testing

@testable import ClaudeTelemetryAdapter

/// C10, on demand only (`SMALTI_BENCH=1`, run by scripts/measure-observatory.sh): reads the user's real
/// `~/.claude` (read-only; the index goes to a temporary file) and prints how long "today" takes to be complete
/// from an empty index, with the app's 1 s read budget, and how long an unchanged refresh takes.
@Suite("Indexing benchmark")
struct IndexingBenchmarkTests {
    @Test func todayFromAnEmptyIndexAndAnUnchangedRefresh() async throws {
        guard ProcessInfo.processInfo.environment["SMALTI_BENCH"] == "1" else { return }
        let index = FileManager.default.temporaryDirectory.appending(path: "smalti-bench-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: index) }
        let home = URL(filePath: NSHomeDirectory()).appending(path: ".claude")
        let transcripts = ClaudeTranscripts(claudeHome: home, indexFile: index, now: { Date() })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let clock = ContinuousClock()
        var calls = 0

        let untilToday = try await clock.measure {
            var activity = try await transcripts.activity(since: today)
            calls = 1
            while activity.indexedSince > today {
                activity = try await transcripts.activity(since: today)
                calls += 1
            }
        }
        var fullCalls = 0
        // The adapter's own window moves with the clock: allow it a minute of drift past the one captured here.
        let window = Date().addingTimeInterval(-ClaudeTranscripts.history + 60)
        let untilWindow = try await clock.measure {
            while try await transcripts.activity(since: window).indexedSince > window { fullCalls += 1 }
        }
        let unchanged = try await clock.measure { _ = try await transcripts.activity(since: today) }

        print("BENCH footprint=\(Self.footprintMegabytes()) MB")
        print(
            "BENCH today=\(untilToday.components.seconds).\(String(format: "%03d", untilToday.components.attoseconds / 1_000_000_000_000_000))s calls=\(calls) "
                + "rest=\(untilWindow) extraCalls=\(fullCalls) unchanged=\(unchanged)")
    }

    /// This process's physical footprint, as Activity Monitor shows it.
    private static func footprintMegabytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            // task_vm_info_data_t is a plain C struct of natural_t-sized fields; the kernel fills `count` of them.
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
