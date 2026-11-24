import Darwin
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "img" {
    let code = await ImageCommand.run(
        Array(arguments.dropFirst()), in: FileManager.default.currentDirectoryPath, terminal: StandardTerminal())
    exit(code)
}
// A hook pipes its JSON on stdin; nothing is read from a terminal, and only `event` reads at all.
let invocation = Invocation(
    arguments: arguments, environment: ProcessInfo.processInfo.environment,
    input: { isatty(STDIN_FILENO) == 1 ? Data() : FileHandle.standardInput.readDataToEndOfFile() })
exit(EventCommand.run(invocation, transport: SocketTransport()))
