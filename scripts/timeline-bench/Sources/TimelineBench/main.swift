import ClaudeHarnessAdapter
import Darwin
import Foundation
import SmaltiCore

// Usage: TimelineBench <claudeHome> <projectRoot> <query> <sessionID>
// Prints one BENCH line: search's first result and whole time over the project (C5), the whole read of the session
// with the rows built (C7) and the resident memory the open session adds (C8). Reads only.

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    FileHandle.standardError.write(Data("usage: TimelineBench <claudeHome> <root> <query> <sessionID>\n".utf8))
    exit(2)
}
let adapter = ClaudeTimeline(projectsRoot: URL(filePath: arguments[1]).appending(path: "projects"))
let clock = ContinuousClock()

func footprint() -> UInt64 {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    return result == 0 ? info.ri_phys_footprint : 0
}

let query = TimelineQuery(arguments[3])
let start = clock.now
var first: Duration?
var matches = 0
for try await hit in adapter.search(query, under: arguments[2]) {
    guard SearchResults.confirm(hit, query: query, policy: VerbatimText()) != nil else { continue }
    if first == nil { first = clock.now - start }
    matches += 1
}
let whole = clock.now - start

let before = footprint()
let readStart = clock.now
let ref = try await adapter.locate(sessionID: arguments[4])
let read = try await adapter.read(ref, from: .start)
let timeline = Timeline().appending(read.entries)
let rows = TimelineRows.rows(
    timeline, harness: .claude, expanded: [], policy: VerbatimText(), texts: .spanish, time: { _ in "" })
let readTime = clock.now - readStart
let size = (try? FileManager.default.attributesOfItem(atPath: ref.file)[.size] as? NSNumber)?.intValue ?? 0
let added = Int64(footprint()) - Int64(before)

func ms(_ duration: Duration?) -> String {
    guard let duration else { return "-" }
    return String(
        format: "%.0f", Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000)
}
print(
    "BENCH search_first_ms=\(ms(first)) search_total_ms=\(ms(whole)) matches=\(matches) "
        + "read_ms=\(ms(readTime)) session_mb=\(size / 1_048_576) rows=\(rows.count) "
        + "memory_added_mb=\(added / 1_048_576) entries=\(read.entries.count)")
