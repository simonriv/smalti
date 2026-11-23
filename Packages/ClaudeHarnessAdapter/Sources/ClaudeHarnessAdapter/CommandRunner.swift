import Foundation

public struct CommandResult: Equatable, Sendable {
    public let status: Int32
    /// Standard output and error, as printed.
    public let output: String
}

/// Runs a command; the installer depends on this, not on `Process`, so tests can point it at a fake `claude`.
public protocol CommandRunner: Sendable {
    func run(_ arguments: [String]) async -> CommandResult
}

/// Runs commands through a shell (`/bin/zsh -lic` in the app, so `claude` is found where the user's `.zshrc` puts
/// it), with an explicit environment.
public struct ShellCommandRunner: CommandRunner {
    /// The shell and its flags, e.g. `["/bin/zsh", "-lic"]`; the command is its last argument.
    let shell: [String]
    let environment: [String: String]

    public init(shell: [String], environment: [String: String]) {
        self.shell = shell
        self.environment = environment
    }

    public func run(_ arguments: [String]) async -> CommandResult {
        await runScript(arguments.map(Self.quoted).joined(separator: " "))
    }

    /// Runs a script as written (hook commands are shell text).
    public func runScript(_ script: String) async -> CommandResult {
        let shell = self.shell
        let environment = self.environment
        return await Task.detached { Self.execute(shell + [script], environment: environment) }.value
    }

    private static func execute(_ command: [String], environment: [String: String]) -> CommandResult {
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
            return CommandResult(status: 127, output: String(describing: error))
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(status: process.terminationStatus, output: text)
    }

    private static let safeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")

    private static func quoted(_ argument: String) -> String {
        guard argument.isEmpty || !argument.allSatisfy(safeCharacters.contains) else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
