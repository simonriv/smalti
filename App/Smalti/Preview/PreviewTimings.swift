import Foundation
import SmaltiCore

/// Measurement hook for F5.5 C3: `-SmaltiPreviewTimings <file>` appends, for every card shown, the milliseconds from
/// the end of the 300 ms wait to the card on screen, one per line. Off unless the argument is given.
@MainActor
final class PreviewTimings {
    static let launchArgument = "SmaltiPreviewTimings"
    private let output: URL
    private var loadStart: ContinuousClock.Instant?

    init?(arguments: UserDefaults = .standard) {
        guard let path = arguments.string(forKey: Self.launchArgument), !path.isEmpty else { return nil }
        output = URL(filePath: path)
    }

    /// The wait ended: the load starts now.
    func loadStarted() {
        loadStart = .now
    }

    func cardShown() {
        guard let start = loadStart else { return }
        loadStart = nil
        let elapsed = ContinuousClock.now - start
        let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        let line = Data(String(format: "%.2f\n", milliseconds).utf8)
        do {
            try append(line)
        } catch {
            // A measurement hook: the run that asked for it reads stderr.
            FileHandle.standardError.write(Data("preview timings: \(error)\n".utf8))
        }
    }

    private func append(_ line: Data) throws {
        guard FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) else {
            try line.write(to: output)
            return
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}

/// A `Debouncer` that tells the timings when its action runs.
@MainActor
final class TimedDebouncer: Debouncer {
    private let inner: any Debouncer
    private let timings: PreviewTimings

    init(_ inner: any Debouncer, timings: PreviewTimings) {
        self.inner = inner
        self.timings = timings
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        inner.schedule { [timings] in
            timings.loadStarted()
            action()
        }
    }

    func cancel() { inner.cancel() }
}
