/// Words written into a pane's shell: ids, paths. Anything outside `[A-Za-z0-9_-]` goes single-quoted.
public enum ShellWord {
    private static let idCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    /// A session id safe to type into a pane: letters, digits, `-` and `_` only. A control character (^U, ^C) would
    /// edit the line in ZLE even inside quotes (review 1, M3), as F2 already guards for Claude's ids.
    public static func isSafeID(_ id: String) -> Bool { !id.isEmpty && id.allSatisfy(idCharacters.contains) }

    /// POSIX-safe in any position of a zsh word; `~` and `=` are not (zsh expands them at a word's start).
    private static let safeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.+,@:")

    public static func quoted(_ text: String) -> String {
        guard text.isEmpty || !text.allSatisfy(safeCharacters.contains) else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
