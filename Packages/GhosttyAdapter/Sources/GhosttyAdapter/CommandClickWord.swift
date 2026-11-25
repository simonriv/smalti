/// libghostty ends a word at ":" (`selection-word-chars`), so ⌘-click on `src/a.ts:12:3` gets `src/a.ts`. The row's
/// text gives the `:12:3` back (spec F6, "Abrir en Neovim").
enum CommandClickWord {
    /// `word` with the `:line` or `:line:column` that follows it in `row`; `column` is the clicked cell, inside the
    /// word, which picks the occurrence when the row repeats it.
    static func extended(_ word: String, row: String, column: Int) -> String {
        let characters = Array(row)
        let length = word.count
        guard length > 0, characters.count >= length else { return word }
        let starts = (0...(characters.count - length)).filter { String(characters[$0..<$0 + length]) == word }
        guard let start = starts.first(where: { $0 <= column && column < $0 + length }) ?? starts.first else {
            return word
        }
        return word + lineSuffix(characters[(start + length)...])
    }

    /// `:12` or `:12:3` at the very start of `rest`; empty otherwise.
    private static func lineSuffix(_ rest: ArraySlice<Character>) -> String {
        var suffix = ""
        var remaining = rest[...]
        for _ in 0..<2 {
            guard remaining.first == ":" else { break }
            let digits = remaining.dropFirst().prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty else { break }
            suffix += ":" + String(digits)
            remaining = remaining.dropFirst(1 + digits.count)
        }
        return suffix
    }
}
