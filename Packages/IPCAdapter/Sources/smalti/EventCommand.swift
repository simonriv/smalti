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
    /// Only the fields the app reads, each cut to `maxFieldLength`: a Write of a large file or a pasted log stays
    /// far below the socket's limit instead of being dropped.
    static func essentials(_ input: Data) -> Data {
        guard let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { return Data() }
        var kept: [String: Any] = [:]
        for key in textFields {
            if let text = object[key] as? String { kept[key] = String(text.prefix(maxFieldLength)) }
        }
        if let tool = object["tool_input"] as? [String: Any] {
            var summary: [String: Any] = toolInputFields.reduce(into: [String: String]()) { fields, key in
                if let text = tool[key] as? String { fields[key] = String(text.prefix(maxFieldLength)) }
            }
            // F6: a MultiEdit's first change locates the line, as an Edit's `new_string` does.
            if let first = (tool["edits"] as? [[String: Any]])?.first?["new_string"] as? String {
                summary["edits"] = [["new_string": String(first.prefix(maxFieldLength))]]
            }
            if !summary.isEmpty { kept["tool_input"] = summary }
        }
        return (try? JSONSerialization.data(withJSONObject: kept)) ?? Data()
    }

    static let version = "0.1.0"
    static let usageError: Int32 = 64
    static let connectTimeout: Duration = .milliseconds(500)
    /// Longest text kept from a field: the app shows a title or a one-line summary.
    static let maxFieldLength = 2_000
    private static let textFields = ["session_id", "prompt", "message", "error", "source", "tool_name"]
    /// F6 adds what file tools wrote, for the line of "Editados por Claude".
    private static let toolInputFields = ["command", "file_path", "notebook_path", "new_string", "content"]

    static func run(_ invocation: Invocation, transport: any EventTransport) -> Int32 {
        switch invocation.arguments.first {
        case "--version":
            print("smalti \(version)")
            return 0
        case "event" where invocation.arguments.count == 2:
            forward(hook: invocation.arguments[1], invocation, transport: transport)
            return 0
        default:
            FileHandle.standardError.write(
                Data("uso: smalti event <Hook> | smalti img [carpeta | archivos…] | smalti --version\n".utf8))
            return usageError
        }
    }

    private static func forward(hook: String, _ invocation: Invocation, transport: any EventTransport) {
        guard let socket = invocation.environment["SMALTI_SOCKET"], !socket.isEmpty,
            let pane = invocation.environment["SMALTI_PANE_ID"], !pane.isEmpty
        else { return }
        guard
            let line = try? IPCCodec.encode(IPCRequest(pane: pane, hook: hook, payload: essentials(invocation.input())))
        else { return }
        try? transport.send(line, to: socket, timeout: connectTimeout)
    }
}
