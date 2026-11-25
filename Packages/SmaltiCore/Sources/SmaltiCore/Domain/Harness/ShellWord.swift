/// Words written into a pane's shell: ids, paths. Anything outside `[A-Za-z0-9_-]` goes single-quoted.
public enum ShellWord {
    private static let safeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    public static func quoted(_ text: String) -> String {
        guard text.isEmpty || !text.allSatisfy(safeCharacters.contains) else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
