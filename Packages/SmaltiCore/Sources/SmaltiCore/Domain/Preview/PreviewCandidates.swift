/// From the word under the pointer to the absolute paths that may hold that image, in the order they are tried
/// (spec F5.5): the word itself (absolute, `~`, or against the pane's directory), then against each directory the
/// pane's last command named, so `ls shots/` works from the parent. Nothing here touches the disk or expands the
/// word: a name is only ever a path.
public enum PreviewCandidates {
    static let wrappers: Set<Character> = ["\"", "'", "(", ")", "[", "]", "<", ">", "`"]
    static let trailing: Set<Character> = [":", ",", ";"]

    public static func paths(for word: String, in context: PreviewContext) -> [String] {
        let name = trimmed(word)
        guard ImageFileKind.isImage(name) else { return [] }
        if name.hasPrefix("/") || name.hasPrefix("~/") { return absolute(name, in: context).map { [$0] } ?? [] }
        if name.hasPrefix("~") { return [] }  // another user's home: not resolved without the disk
        guard let directory = context.workingDirectory else { return [] }
        let folders = [directory] + commandDirectories(context)
        var seen = Set<String>()
        return folders.map { PathNormalizer.normalize("\($0)/\(name)") }.filter { seen.insert($0).inserted }
    }

    private static func trimmed(_ word: String) -> String {
        var text = Substring(word)
        while let last = text.last, trailing.contains(last) || wrappers.contains(last) { text = text.dropLast() }
        while let first = text.first, wrappers.contains(first) { text = text.dropFirst() }
        return String(text)
    }

    /// Each argument of the last simple command of the line (`cd x && ls shots` gives `shots`) that may be a directory,
    /// resolved; options and the command itself are skipped.
    private static func commandDirectories(_ context: PreviewContext) -> [String] {
        guard let command = context.lastCommand else { return [] }
        let line = InputLine(text: command, cursor: command.unicodeScalars.count)
        return line.currentCommand.dropFirst().map(\.text).filter { !$0.isEmpty && !$0.hasPrefix("-") }.compactMap {
            absolute($0, in: context)
        }
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
