import Darwin
import Foundation

// A hook pipes its JSON on stdin; nothing is read from a terminal.
let input = isatty(STDIN_FILENO) == 1 ? Data() : FileHandle.standardInput.readDataToEndOfFile()
let invocation = Invocation(
    arguments: Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment,
    input: input)
exit(EventCommand.run(invocation, transport: SocketTransport()))
