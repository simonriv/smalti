import Foundation

public struct CommandResult: Equatable, Sendable {
    /// `launchFailed` when the shell itself could not start.
    public static let launchFailed: Int32 = -1

    public let status: Int32
    /// Standard output and error, as printed.
    public let output: String
}

/// Runs a command; the installer depends on this, not on `Process`, so tests can point it at a fake `claude`.
public protocol CommandRunner: Sendable {
    /// What starts the commands, for error messages (e.g. `/bin/zsh`).
    var launcher: String { get }
    func run(_ arguments: [String]) async -> CommandResult
}

/// Runs commands through a shell (`/bin/zsh -lic` in the app, so `claude` is found where the user's `.zshrc` puts
/// it), with an explicit environment.
public struct ShellCommandRunner: CommandRunner {
    /// The shell and its flags, e.g. `["/bin/zsh", "-lic"]`; the command is its last argument.
    let shell: [String]
    let environment: [String: String]
    /// A command still running after this is stopped (an rc file that starts a daemon would block forever).
    let timeout: Duration

    public init(shell: [String], environment: [String: String], timeout: Duration = .seconds(120)) {
        self.shell = shell
        self.environment = environment
        self.timeout = timeout
    }

    public var launcher: String { shell.first ?? "" }

    public func run(_ arguments: [String]) async -> CommandResult {
        await runScript(arguments.map(Self.quoted).joined(separator: " "))
    }

    /// Runs a script as written (hook commands are shell text).
    public func runScript(_ script: String) async -> CommandResult {
        let shell = self.shell
        let environment = self.environment
        let timeout = self.timeout
        return await Task.detached { Self.execute(shell + [script], environment: environment, timeout: timeout) }.value
    }

    private static func execute(_ command: [String], environment: [String: String], timeout: Duration) -> CommandResult
    {
        let process = Process()
        process.executableURL = URL(filePath: command[0])
        process.arguments = Array(command.dropFirst())
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return CommandResult(status: CommandResult.launchFailed, output: String(describing: error))
        }
        let watchdog = DispatchWorkItem { [process] in if process.isRunning { process.terminate() } }
        let parts = timeout.components
        DispatchQueue.global().asyncAfter(
            deadline: .now() + .seconds(Int(parts.seconds)) + .nanoseconds(Int(parts.attoseconds / 1_000_000_000)),
            execute: watchdog)
        // Stops waiting on output a terminated command's descendants may keep open.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(status: process.terminationStatus, output: text)
    }

    private static let safeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")

    private static func quoted(_ argument: String) -> String {
        guard argument.isEmpty || !argument.allSatisfy(safeCharacters.contains) else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
