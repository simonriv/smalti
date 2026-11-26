import Foundation
import Synchronization
import Testing

@testable import JSONLReader

@Suite struct FileWatchTests {
    /// Descriptors of this process open on `file` (suites run in parallel, so only this test's file counts).
    private static func descriptors(on file: URL) -> Int {
        let target = file.resolvingSymlinksInPath().path(percentEncoded: false)
        return (0..<Int32(getdtablesize())).filter { descriptor in
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &path) != -1 else { return false }
            return URL(filePath: String(cString: path)).resolvingSymlinksInPath().path(percentEncoded: false) == target
        }.count
    }

    private static func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aBurstOfWritesTellsOnce() async throws {
        let file = try TemporaryFile("a\n")
        let changes = Mutex(0)
        let watch = try FileWatch(file: file.url, coalescing: .milliseconds(150)) { changes.withLock { $0 += 1 } }

        try file.append("b\n")
        try file.append("c\n")
        try file.append("d\n")
        await Self.waitUntil { changes.withLock { $0 } > 0 }
        try await Task.sleep(for: .milliseconds(300))

        #expect(changes.withLock { $0 } == 1)
        watch.cancel()
    }

    @Test func cancellingClosesTheDescriptorAndStopsTelling() async throws {
        let file = try TemporaryFile("a\n")
        let changes = Mutex(0)
        let watch = try FileWatch(file: file.url, coalescing: .milliseconds(20)) { changes.withLock { $0 += 1 } }
        #expect(Self.descriptors(on: file.url) == 1)

        watch.cancel()
        try file.append("b\n")
        await Self.waitUntil { Self.descriptors(on: file.url) == 0 }
        try await Task.sleep(for: .milliseconds(200))

        #expect(Self.descriptors(on: file.url) == 0)
        #expect(changes.withLock { $0 } == 0)
    }

    @Test func releasingTheWatchCancelsIt() async throws {
        let file = try TemporaryFile("a\n")
        do {
            let watch = try FileWatch(file: file.url, coalescing: .milliseconds(20)) {}
            #expect(Self.descriptors(on: file.url) == 1)
            _ = watch
        }
        await Self.waitUntil { Self.descriptors(on: file.url) == 0 }

        #expect(Self.descriptors(on: file.url) == 0)
    }

    @Test func aMissingFileThrows() {
        #expect(throws: JSONLReadError.self) {
            _ = try FileWatch(file: URL(filePath: "/nonexistent/\(UUID().uuidString)"), coalescing: .zero) {}
        }
    }
}
