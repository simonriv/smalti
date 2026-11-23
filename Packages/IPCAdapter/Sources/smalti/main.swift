import Darwin
import Foundation

// A hook pipes its JSON on stdin; nothing is read from a terminal, and only `event` reads at all.
let invocation = Invocation(
    arguments: Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment,
    input: { isatty(STDIN_FILENO) == 1 ? Data() : FileHandle.standardInput.readDataToEndOfFile() })
exit(EventCommand.run(invocation, transport: SocketTransport()))
