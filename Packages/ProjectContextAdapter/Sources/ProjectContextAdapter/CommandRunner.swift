import Foundation

/// Runs a command for the prompt's facts (spec F5) and gives its standard output. A slow repository leaves its module
/// out instead of making the prompt wait, so callers treat every error as "no fact".
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], in directory: String, timeout: Duration)
        async throws(CommandError) -> String
}

public enum CommandError: Error, Equatable, Sendable {
    case couldNotStart
    case timedOut
    case failed(status: Int32)
}

/// The real runner: a child process with no input. Its output is collected as it arrives, off the concurrency
/// pool, and the answer is ready when the child ends, even if a grandchild keeps the pipe open (block 3 review, I3);
/// at the timeout the child is killed and the pipe closed.
public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], in directory: String, timeout: Duration)
        async throws(CommandError) -> String
    {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(filePath: directory)
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        let collected = OutputCollector(output.fileHandleForReading)
        let ended = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }
        do {
            try process.run()
        } catch {
            collected.close()
            throw .couldNotStart
        }
        guard let status = await Self.status(of: ended, within: timeout) else {
            process.terminate()
            collected.close()
            throw .timedOut
        }
        let text = collected.finish()
        guard status == 0 else { throw .failed(status: status) }
        return text
    }

    /// The child's exit status, or `nil` when `timeout` passes first.
    private static func status(of ended: AsyncStream<Int32>, within timeout: Duration) async -> Int32? {
        await withTaskGroup(of: Int32?.self) { group in
            group.addTask {
                for await status in ended { return status }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Collects a pipe's bytes through `readabilityHandler` (a dispatch source, not a blocked thread).
private final class OutputCollector: @unchecked Sendable {
    // Safe: `data` and `isClosed` are only touched under `lock`.
    private let lock = NSLock()
    private var data = Data()
    private var isClosed = false
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] readable in
            let chunk = readable.availableData
            self?.lock.withLock {
                if !(self?.isClosed ?? true) { self?.data.append(chunk) }
            }
        }
    }

    /// What arrived up to now plus whatever is already waiting, without waiting for the end of the pipe.
    func finish() -> String {
        let pending = Self.drain(handle)
        let text = lock.withLock { () -> String in
            data.append(pending)
            return String(decoding: data, as: UTF8.self)
        }
        close()
        return text
    }

    func close() {
        let wasOpen = lock.withLock { () -> Bool in
            defer { isClosed = true }
            return !isClosed
        }
        guard wasOpen else { return }
        handle.readabilityHandler = nil
        try? handle.close()
    }

    /// Bytes already in the pipe, read without blocking.
    private static func drain(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer[0..<count])
        }
        return result
    }
}
