/// One command of a shell line, after its `NAME=value` assignments and its wrappers (`sudo`, `npx`, `env`…) are
/// taken off (spec F7.5, «Comandos que piden aprobación»).
public struct SimpleCommand: Equatable, Sendable {
    public let assignments: [String: String]
    /// Every word of the command as written, wrappers included.
    public let words: [String]
    public let redirections: [String]
    /// The base name of the program that really runs (`./node_modules/.bin/prisma` → `prisma`); nil when the
    /// command is only assignments or redirections.
    public let program: String?
    /// The words after the program.
    public let arguments: [String]
    /// The command's source text, quotes and all.
    public let rawText: String
}

/// Splits a shell line into the simple commands a guard must look at, the nested ones included: `sh/bash/zsh -c`,
/// `eval`, `$( … )`, backquotes and the remote command of `ssh`, down to `maximumDepth` levels.
public enum ShellCommandLine {
    public static let maximumDepth = 4

    public static func commands(in text: String, home: String) -> [SimpleCommand] {
        commands(in: text, home: home, depth: 0)
    }

    private static func commands(in text: String, home: String, depth: Int) -> [SimpleCommand] {
        ShellLexer.segments(of: text, home: home).flatMap { segment in
            let command = simpleCommand(from: segment)
            guard depth < maximumDepth else { return [command] }
            let nested = (nestedScript(of: command).map { [$0] } ?? []) + segment.substitutions
            return [command] + nested.flatMap { commands(in: $0, home: home, depth: depth + 1) }
        }
    }

    static func simpleCommand(from segment: LexedSegment) -> SimpleCommand {
        var assignments: [String: String] = [:]
        var rest = segment.words[...]
        while let first = rest.first, let (name, value) = assignment(first) {
            assignments[name] = value
            rest = rest.dropFirst()
        }
        rest = ShellWrappers.strip(rest, into: &assignments)
        let program = rest.first.map(baseName)
        return SimpleCommand(
            assignments: assignments, words: segment.words, redirections: segment.redirections, program: program,
            arguments: Array(rest.dropFirst()), rawText: segment.rawText)
    }

    /// `NAME=value` with a valid shell name.
    static func assignment(_ word: String) -> (String, String)? {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return nil }
        let name = word[..<equals]
        guard let first = name.first, first.isLetter || first == "_",
            name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return nil }
        return (String(name), String(word[word.index(after: equals)...]))
    }

    static func baseName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The script a command runs itself: `bash -c '<script>'`, `eval <words>`, `ssh host <command>`.
    private static func nestedScript(of command: SimpleCommand) -> String? {
        switch command.program {
        case "sh", "bash", "zsh", "dash", "ksh": shellScript(command.arguments)
        case "eval": command.arguments.isEmpty ? nil : command.arguments.joined(separator: " ")
        case "ssh": remoteCommand(command.arguments)
        default: nil
        }
    }

    /// The word after the first option that holds `c` (`-c`, `-lc`, `-ec`).
    private static func shellScript(_ arguments: [String]) -> String? {
        guard
            let flag = arguments.firstIndex(where: { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("c") }),
            flag + 1 < arguments.count
        else { return nil }
        return arguments[flag + 1]
    }

    private static let sshOptionsWithValue: Set<String> = [
        "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m", "-O", "-o", "-p", "-Q", "-R", "-S",
        "-W", "-w",
    ]

    /// What follows the host in `ssh [options] host command…`.
    private static func remoteCommand(_ arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count, arguments[index].hasPrefix("-") {
            index += sshOptionsWithValue.contains(arguments[index]) ? 2 : 1
        }
        let command = arguments.dropFirst(index + 1)
        return command.isEmpty ? nil : command.joined(separator: " ")
    }
}
