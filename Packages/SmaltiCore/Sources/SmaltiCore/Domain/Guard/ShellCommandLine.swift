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
    /// Its here-document bodies, as data.
    public let heredocs: [String]
}

/// A shell line split into commands, and whether some of it was nested deeper than the guard looks.
public struct ShellAnalysis: Sendable {
    public let commands: [SimpleCommand]
    public let isTooDeep: Bool
}

/// Splits a shell line into the simple commands a guard must look at, the nested ones included: `sh/bash/zsh -c`,
/// `eval`, `$( … )`, backquotes and the remote command of `ssh`, down to `maximumDepth` levels.
public enum ShellCommandLine {
    public static let maximumDepth = 4

    public static func commands(in text: String, home: String) -> [SimpleCommand] {
        analysis(in: text, home: home).commands
    }

    /// The commands, and whether some nested script was left unread past `maximumDepth` (review 1: that asks).
    public static func analysis(in text: String, home: String) -> ShellAnalysis {
        var isTooDeep = false
        let found = commands(in: text, home: home, depth: 0, isTooDeep: &isTooDeep)
        return ShellAnalysis(commands: found, isTooDeep: isTooDeep)
    }

    private static func commands(in text: String, home: String, depth: Int, isTooDeep: inout Bool) -> [SimpleCommand] {
        var found: [SimpleCommand] = []
        for segment in ShellLexer.segments(of: text, home: home) {
            let command = simpleCommand(from: segment)
            found.append(command)
            let nested = nestedScripts(of: command) + segment.substitutions
            guard !nested.isEmpty else { continue }
            guard depth < maximumDepth else {
                isTooDeep = true
                continue
            }
            for script in nested {
                found += commands(in: script, home: home, depth: depth + 1, isTooDeep: &isTooDeep)
            }
        }
        return found
    }

    static func simpleCommand(from segment: LexedSegment) -> SimpleCommand {
        var assignments: [String: String] = [:]
        let rest = ShellWrappers.strip(segment.words[...], into: &assignments)
        let program = rest.first.map(baseName)
        return SimpleCommand(
            assignments: assignments, words: segment.words, redirections: segment.redirections, program: program,
            arguments: Array(rest.dropFirst()), rawText: segment.rawText, heredocs: segment.heredocs)
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

    /// The program's name without its folder nor an npm version (`supabase@latest` → `supabase`).
    static func baseName(_ path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let at = name.firstIndex(of: "@"), at != name.startIndex else { return name }
        return String(name[..<at])
    }

    /// The scripts a command runs itself: `bash -c '<script>'`, a shell fed a here-document, `eval <words>`,
    /// `ssh host <command>`.
    private static func nestedScripts(of command: SimpleCommand) -> [String] {
        switch command.program {
        case "sh", "bash", "zsh", "dash", "ksh": shellScript(command.arguments).map { [$0] } ?? command.heredocs
        case "eval": command.arguments.isEmpty ? [] : [command.arguments.joined(separator: " ")]
        case "ssh": remoteCommand(command.arguments).map { [$0] } ?? []
        default: []
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
