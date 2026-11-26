import DarwinProcessesAdapter
import Foundation
import SmaltiCore
import Testing

@Suite("DarwinRunningProcesses", .serialized, .timeLimit(.minutes(1)))
struct RunningProcessesTests {
    private let processes = DarwinRunningProcesses()

    @Test func childAppearsWithParentArgumentsDirectoryAndStart() async throws {
        let directory = FileManager.default.temporaryDirectory
        let child = try Child.sleeper(directory: directory)
        defer { child.end() }

        let sample = await processes.current()

        let record = try #require(sample.records.first { $0.pid == child.pid })
        #expect(record.isOwn)
        #expect(record.parent == getpid())
        // /usr/bin/python3 is a shim that execs Xcode's Python: the arguments after the program are what we passed.
        #expect(Array(record.arguments.dropFirst().prefix(2)) == ["-u", "-c"])
        #expect(record.workingDirectory == Self.realPath(directory))
        #expect(abs(record.identity.startedAt.timeIntervalSinceNow) < 60)
        #expect(record.memory > 0)
        #expect(record.threads >= 1)
        #expect(record.nice == 0)
        #expect(record.executable?.hasPrefix("/") == true)
    }

    @Test func otherUsersProcessesAreCountedButNotRead() async throws {
        let sample = await processes.current()

        let launchd = try #require(sample.records.first { $0.pid == 1 })
        #expect(!launchd.isOwn)
        #expect(launchd.arguments.isEmpty)
        #expect(launchd.workingDirectory == nil)
        #expect(sample.hiddenCount == sample.records.filter { !$0.isOwn }.count)
        #expect(sample.hiddenCount > 0)
        #expect(sample.memoryTotal > 0)
    }

    @Test func ownProcessIsThereWithItsStart() async throws {
        let sample = await processes.current()

        let own = try #require(sample.records.first { $0.pid == getpid() })
        #expect(own.isOwn)
        #expect(own.run == .running || own.run == .sleeping)
    }

    @Test func cpuTimeOfASpinningChildGrows() async throws {
        let child = try Child.spinner()
        defer { child.end() }
        let first = await processes.current()
        try await Task.sleep(for: .milliseconds(400))

        let second = await processes.current()

        let usage = CPUUsage.percentages(previous: first, current: second)
        let identity = try #require(second.records.first { $0.pid == child.pid }?.identity)
        #expect((usage[identity] ?? 0) > 30)
        #expect(second.takenAt > first.takenAt)
    }

    @Test func childWithoutTerminalHasNone() async throws {
        let child = try Child.sleeper()
        defer { child.end() }

        let sample = await processes.current()

        #expect(sample.records.first { $0.pid == child.pid }?.terminal == nil)
    }
}

extension RunningProcessesTests {
    /// The kernel reports the real path (`/private/var/…`); Foundation would drop `/private`.
    fileprivate static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path(percentEncoded: false), nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
