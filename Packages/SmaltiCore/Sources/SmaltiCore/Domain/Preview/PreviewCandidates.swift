/// From the word under the pointer to the absolute paths that may hold that image, in the order they are tried
/// (spec F5.5): an absolute or `~` word as is; a relative one first against each directory the pane's last command
/// named (so `ls shots/` shows shots' `a.png`, never the parent's), then against the pane's directory. Nothing here touches the disk or expands the
/// word: a name is only ever a path.
public enum PreviewCandidates {
    static let wrappers: Set<Character> = ["\"", "'", "(", ")", "[", "]", "<", ">", "`"]
    static let trailing: Set<Character> = [":", ",", ";", "."]

    public static func paths(for word: String, in context: PreviewContext) -> [String] {
        let name = trimmed(word)
        guard ImageFileKind.isImage(name) else { return [] }
        if name.hasPrefix("/") || name.hasPrefix("~/") { return absolute(name, in: context).map { [$0] } ?? [] }
        if name.hasPrefix("~") { return [] }  // another user's home: not resolved without the disk
        guard let directory = context.workingDirectory else { return [] }
        let folders = commandDirectories(context) + [directory]
        var seen = Set<String>()
        return folders.map { PathNormalizer.normalize("\($0)/\(name)") }.filter { seen.insert($0).inserted }
    }

    private static func trimmed(_ word: String) -> String {
        var text = Substring(word)
        while let last = text.last, trailing.contains(last) || wrappers.contains(last) { text = text.dropLast() }
        while let first = text.first, wrappers.contains(first) { text = text.dropFirst() }
        return String(text)
    }

    /// Each argument of every command of the last line (`ls -t shots | head` gives `shots` and `head`'s) that may be
    /// a directory, resolved; commands, options, redirections and their targets are skipped.
    private static func commandDirectories(_ context: PreviewContext) -> [String] {
        guard let command = context.lastCommand else { return [] }
        return ShellWords.commands(in: command).flatMap { arguments(of: $0.map(\.text)) }.compactMap {
            absolute($0, in: context)
        }
    }

    private static func arguments(of words: [String]) -> [String] {
        var arguments: [String] = []
        var isRedirectTarget = false
        for word in words.dropFirst() {
            if isRedirectTarget {
                isRedirectTarget = false
            } else if Redirection.isOperator(word) {
                isRedirectTarget = true
            } else if !word.isEmpty && !word.hasPrefix("-") && !Redirection.isAttached(word) {
                arguments.append(word)
            }
        }
        return arguments
    }

    private static func absolute(_ path: String, in context: PreviewContext) -> String? {
        if path.hasPrefix("/") { return PathNormalizer.normalize(path) }
        if path == "~" || path.hasPrefix("~/") { return PathNormalizer.normalize(context.home + path.dropFirst()) }
        guard let directory = context.workingDirectory else { return nil }
        return PathNormalizer.normalize("\(directory)/\(path)")
    }
}

/// Lexical normalization of an absolute path: `.` and `..` segments and repeated or trailing slashes go away.
enum PathNormalizer {
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
}

/// Shell redirections in a command's words: `>`, `2>`, `&>`, `<` alone (the next word is their target) or attached
/// to it (`>out.txt`, `2>&1`).
enum Redirection {
    private static let operatorCharacters: Set<Character> = ["<", ">", "&"]

    static func isOperator(_ word: String) -> Bool {
        let body = word.drop { $0.isASCII && $0.isNumber }
        return !body.isEmpty && body.allSatisfy(operatorCharacters.contains) && body.contains { $0 != "&" }
    }

    static func isAttached(_ word: String) -> Bool {
        let body = word.drop { $0.isASCII && $0.isNumber }
        return body.hasPrefix(">") || body.hasPrefix("<") || body.hasPrefix("&>")
    }
}
