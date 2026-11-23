/// Writes a name as one zsh word, the way `${(q)}` would: escaped with backslashes outside quotes, or as the inside
/// of the word's own opening quote (which the caller re-opens and closes).
enum ShellQuoting {
    /// Characters zsh gives a meaning to anywhere in an unquoted word.
    private static let metacharacters: Set<Character> = [
        " ", "\t", "\n", "'", "\"", "\\", "$", "`", "!", "&", "|", ";", "<", ">", "(", ")", "[", "]", "{", "}", "*",
        "?", "#", "^",
    ]
    /// Characters with a meaning only at the start of a word (`~user`, `=cmd`).
    private static let leadingMetacharacters: Set<Character> = ["~", "="]

    /// The word's opening quote, if any, followed by the quoted name; the caller closes the quote.
    static func word(_ name: String, opening: Character?) -> String {
        (opening.map(String.init) ?? "") + quote(name, inside: opening)
    }

    static func quote(_ name: String, inside opening: Character?) -> String {
        switch opening {
        case "'": name.replacingOccurrences(of: "'", with: "'\\''")
        case "\"": escape(name, in: ["\"", "\\", "$", "`"])
        default: escapeUnquoted(name)
        }
    }

    private static func escapeUnquoted(_ name: String) -> String {
        var result = ""
        for (offset, character) in name.enumerated() {
            let needsEscape =
                metacharacters.contains(character) || (offset == 0 && leadingMetacharacters.contains(character))
            if needsEscape { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func escape(_ name: String, in characters: Set<Character>) -> String {
        name.reduce(into: "") { result, character in
            if characters.contains(character) { result.append("\\") }
            result.append(character)
        }
    }
}
