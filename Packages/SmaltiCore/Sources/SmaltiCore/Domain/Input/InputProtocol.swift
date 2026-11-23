import Foundation

/// What a pane's zsh tells Smalti over the input socket.
public enum ShellMessage: Equatable, Sendable {
    case hello(PaneID)
    case line(seq: Int, InputLine)
    case exec(seq: Int, command: String)
    case done(seq: Int, exit: Int)
    case complete(seq: Int, InputLine)
    case history(seq: Int, query: String)
    case bye
}

/// One message from zsh with the directory it was sent from (`$PWD`), when the message carries one: `line`,
/// `exec`, `complete` and `history` do, so a `cd` just before never races the terminal's OSC 7.
public struct ShellPacket: Equatable, Sendable {
    public let message: ShellMessage
    public let directory: String?

    public init(_ message: ShellMessage, directory: String? = nil) {
        self.message = message
        self.directory = directory
    }
}

/// What Smalti answers. zsh drops any answer whose `seq` is not the last one it sent. `edit` with `thenEnter` is
/// the edit of ⌘↩: Smalti types Return right after it, and zsh refuses that Return if it dropped the edit.
public enum SmaltiMessage: Equatable, Sendable {
    case specs([String])
    case suggest(seq: Int, String)
    case edit(seq: Int, InputLine, thenEnter: Bool = false)
    case fallback(seq: Int)
}

public struct InputProtocolError: Error, Equatable, Sendable {
    public let line: String
    public let cause: String

    public init(line: String, cause: String) {
        self.line = line
        self.cause = cause
    }
}

/// One message per line; fields separated by tabs, with `\t`, `\n` and `\\` escaped inside them.
public enum InputProtocol {
    /// A message this long or longer is not sent: zsh clears the ghost instead of suggesting on a huge paste. It
    /// stays under the socket's low-water mark (2048 bytes on Darwin), the room `zselect -w` guarantees, so a
    /// write never blocks the shell.
    public static let maxLineBytes = 1999

    /// `line <seq> <pwd> <cursor> <buffer>`, `exec <seq> <pwd> <command>`, `complete <seq> <pwd> <cursor> <buffer>`,
    /// `history <seq> <pwd> <query>`, `done <seq> <exit>`, `hello <pane>`, `bye`.
    public static func decode(_ line: String) throws(InputProtocolError) -> ShellPacket {
        var fields = Fields(line: line)
        let verb = try fields.next()
        switch verb {
        case "hello": return ShellPacket(.hello(try fields.pane()))
        case "line":
            let (seq, directory) = (try fields.int(), try fields.next())
            return ShellPacket(.line(seq: seq, try fields.inputLine()), directory: directory)
        case "exec":
            let (seq, directory) = (try fields.int(), try fields.next())
            return ShellPacket(.exec(seq: seq, command: try fields.next()), directory: directory)
        case "done": return ShellPacket(.done(seq: try fields.int(), exit: try fields.int()))
        case "complete":
            let (seq, directory) = (try fields.int(), try fields.next())
            return ShellPacket(.complete(seq: seq, try fields.inputLine()), directory: directory)
        case "history":
            let (seq, directory) = (try fields.int(), try fields.next())
            return ShellPacket(.history(seq: seq, query: try fields.next()), directory: directory)
        case "bye": return ShellPacket(.bye)
        default: throw InputProtocolError(line: line, cause: "unknown message \"\(verb)\"")
        }
    }

    public static func encode(_ message: SmaltiMessage) -> String {
        switch message {
        case .specs(let commands): join("specs", commands.joined(separator: " "))
        case .suggest(let seq, let text): join("suggest", String(seq), text)
        case .edit(let seq, let line, let thenEnter):
            join(thenEnter ? "editrun" : "edit", String(seq), String(line.cursor), line.text)
        case .fallback(let seq): join("fallback", String(seq))
        }
    }

    /// The shell side's encoding, for tests and the benchmark; nil when the line exceeds `maxLineBytes`.
    public static func encode(_ packet: ShellPacket) -> String? {
        let encoded = fields(of: packet.message, directory: packet.directory ?? "/")
        return encoded.utf8.count > maxLineBytes ? nil : encoded
    }

    private static func fields(of message: ShellMessage, directory: String) -> String {
        switch message {
        case .hello(let pane): join("hello", pane.description)
        case .line(let seq, let line): join("line", String(seq), directory, String(line.cursor), line.text)
        case .exec(let seq, let command): join("exec", String(seq), directory, command)
        case .done(let seq, let exit): join("done", String(seq), String(exit))
        case .complete(let seq, let line): join("complete", String(seq), directory, String(line.cursor), line.text)
        case .history(let seq, let query): join("history", String(seq), directory, query)
        case .bye: "bye"
        }
    }

    private static func join(_ fields: String...) -> String {
        fields.map(escape).joined(separator: "\t")
    }

    static func escape(_ field: String) -> String {
        field.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func unescape(_ field: Substring) -> String {
        var result = ""
        var isEscaped = false
        for character in field {
            if isEscaped {
                result.append(character == "t" ? "\t" : character == "n" ? "\n" : character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private struct Fields {
        let line: String
        private var remaining: ArraySlice<Substring>

        init(line: String) {
            self.line = line
            remaining = ArraySlice(line.split(separator: "\t", omittingEmptySubsequences: false))
        }

        mutating func next() throws(InputProtocolError) -> String {
            guard let field = remaining.popFirst() else {
                throw InputProtocolError(line: line, cause: "missing field")
            }
            return InputProtocol.unescape(field)
        }

        mutating func int() throws(InputProtocolError) -> Int {
            let field = try next()
            guard let value = Int(field) else {
                throw InputProtocolError(line: line, cause: "\"\(field)\" is not a number")
            }
            return value
        }

        mutating func pane() throws(InputProtocolError) -> PaneID {
            let field = try next()
            guard let uuid = UUID(uuidString: field) else {
                throw InputProtocolError(line: line, cause: "\"\(field)\" is not a pane id")
            }
            return PaneID(rawValue: uuid)
        }

        mutating func inputLine() throws(InputProtocolError) -> InputLine {
            let cursor = try int()
            return InputLine(text: try next(), cursor: cursor)
        }
    }
}
