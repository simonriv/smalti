import Foundation

/// Runs a command for the prompt's facts (spec F5) and gives its standard output, or `nil` when it fails, cannot
/// start or takes longer than `timeout`, so a slow repository leaves its module out instead of waiting.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], in directory: String, timeout: Duration) async -> String?
}

/// The real runner: a child process with no input, killed at the timeout.
public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], in directory: String, timeout: Duration) async
        -> String?
    {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(filePath: directory)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.finish() }
        }
        do {
            try process.run()
        } catch {
            return nil
        }
        let reader = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in finished {}
                return true
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard completed else {
            process.terminate()
            reader.cancel()
            return nil
        }
        let data = await reader.value
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
