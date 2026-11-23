import Foundation
import SmaltiCore

/// Runs the commands of Fig generators: argument lists directly, strings through `zsh -f -c`, in the pane's
/// directory with a minimal environment. A run past `timeout` is killed and fails without waiting for the rest
/// of its output. When the process exits but a background child keeps the pipe open, what arrived within a short
/// grace period is the output. Output beyond `maximumOutput` bytes is dropped.
///
/// Every run is offline: it goes through `sandbox-exec` with outgoing IP connections denied, because some Fig
/// generators ask remote registries about what was typed (`npm install <word>`). Without `sandbox-exec` the run
/// fails rather than go out unconfined.
public struct GeneratorRunner: Sendable {
    static let sandbox = URL(filePath: "/usr/bin/sandbox-exec")
    static let offlineProfile = "(version 1)(allow default)(deny network-outbound (remote ip))"
    static let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    static let maximumOutput = 1 << 20
    static let exitGrace: Duration = .milliseconds(50)

    public let timeout: Duration

    public init(timeout: Duration) {
        self.timeout = timeout
    }

    public struct Output: Sendable {
        public let stdout: String
        public let status: Int32
    }

    public func run(arguments: [String], in directory: String) async throws(CompletionError) -> Output {
        try await execute(["/usr/bin/env"] + arguments, in: directory)
    }

    public func run(shell script: String, in directory: String) async throws(CompletionError) -> Output {
        try await execute(["/bin/zsh", "-f", "-c", script], in: directory)
    }

    private func execute(_ arguments: [String], in directory: String) async throws(CompletionError) -> Output {
        let command = arguments.joined(separator: " ")
        let process = Process()
        process.executableURL = Self.sandbox
        process.arguments = ["-p", Self.offlineProfile] + arguments
        process.currentDirectoryURL = URL(filePath: directory)
        process.environment = ["PATH": Self.path, "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let collector = RunCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            collector.receive(data)
        }
        process.terminationHandler = { finished in
            collector.exited(status: finished.terminationStatus)
            Task {
                try? await Task.sleep(for: Self.exitGrace)
                collector.giveUpOnOutput()
            }
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw CompletionError(command: command, cause: "could not start: \(error)")
        }
        let timeout = timeout
        // Safe: the deadline task only calls `terminate()`, which `Process` allows from any thread.
        nonisolated(unsafe) let running = process
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            if collector.timeOut() { running.terminate() }
        }
        let result = await collector.result()
        deadline.cancel()
        guard let result else {
            throw CompletionError(command: command, cause: "timed out after \(timeout)")
        }
        return result
    }
}

/// Joins a run's output, its exit and its deadline; the first of "output closed and process exited" or "timed
/// out" wins. Every member is guarded by `lock`, so it is safe to share between Foundation's handler threads.
private final class RunCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var isOutputClosed = false
    private var status: Int32?
    private var isDone = false
    private var waiter: CheckedContinuation<GeneratorRunner.Output?, Never>?
    private var outcome: GeneratorRunner.Output??

    func receive(_ chunk: Data) {
        lock.withLock {
            if chunk.isEmpty {
                isOutputClosed = true
            } else if data.count < GeneratorRunner.maximumOutput {
                data.append(chunk.prefix(GeneratorRunner.maximumOutput - data.count))
            }
        }
        finishIfComplete()
    }

    func exited(status code: Int32) {
        lock.withLock { status = code }
        finishIfComplete()
    }

    /// The process exited a moment ago and the pipe is still open (a background child holds it): what arrived is
    /// the output.
    func giveUpOnOutput() {
        lock.withLock { isOutputClosed = true }
        finishIfComplete()
    }

    /// Ends the wait as timed out; false when the run had already finished.
    func timeOut() -> Bool {
        lock.withLock { complete(with: .some(nil)) }
    }

    func result() async -> GeneratorRunner.Output? {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if let outcome { continuation.resume(returning: outcome) } else { waiter = continuation }
            }
        }
    }

    private func finishIfComplete() {
        lock.withLock {
            guard isOutputClosed, let status else { return }
            _ = complete(
                with: .some(GeneratorRunner.Output(stdout: String(decoding: data, as: UTF8.self), status: status)))
        }
    }

    /// Called with `lock` held.
    private func complete(with value: GeneratorRunner.Output??) -> Bool {
        guard !isDone, let value else { return false }
        isDone = true
        outcome = value
        waiter?.resume(returning: value)
        waiter = nil
        return true
    }
}
