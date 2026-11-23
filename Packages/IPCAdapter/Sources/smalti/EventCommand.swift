import Foundation
import SmaltiIPCProtocol

/// What the CLI was asked: its arguments (without the program name), its environment and, read only when needed,
/// its standard input.
struct Invocation {
    let arguments: [String]
    let environment: [String: String]
    let input: () -> Data
}

enum TransportError: Error {
    case unreachable(String)
}

/// How a request reaches the app; the real one is a Unix socket with a short timeout.
protocol EventTransport: Sendable {
    func send(_ line: Data, to socket: String, timeout: Duration) throws(TransportError)
}

/// `smalti event <Hook>` forwards a Claude Code hook's JSON (stdin) to the Smalti that runs the pane. It never fails
/// a hook: without the app, the socket or the pane it exits 0 silently, within a second.
enum EventCommand {
    static let version = "0.1.0"
    static let usageError: Int32 = 64
    static let connectTimeout: Duration = .milliseconds(500)

    static func run(_ invocation: Invocation, transport: any EventTransport) -> Int32 {
        switch invocation.arguments.first {
        case "--version":
            print("smalti \(version)")
            return 0
        case "event" where invocation.arguments.count == 2:
            forward(hook: invocation.arguments[1], invocation, transport: transport)
            return 0
        default:
            FileHandle.standardError.write(Data("uso: smalti event <Hook> | smalti --version\n".utf8))
            return usageError
        }
    }

    private static func forward(hook: String, _ invocation: Invocation, transport: any EventTransport) {
        guard let socket = invocation.environment["SMALTI_SOCKET"], !socket.isEmpty,
            let pane = invocation.environment["SMALTI_PANE_ID"], !pane.isEmpty
        else { return }
        let input = invocation.input()
        guard input.count <= IPCLimits.maxMessageBytes,
            let line = try? IPCCodec.encode(IPCRequest(pane: pane, hook: hook, payload: input))
        else { return }
        try? transport.send(line, to: socket, timeout: connectTimeout)
    }
}
