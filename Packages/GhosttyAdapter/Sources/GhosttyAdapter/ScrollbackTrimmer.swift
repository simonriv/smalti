/// Keeps the last lines of an exported scrollback and starts it with an SGR reset, so a cut through a coloured
/// line does not tint what follows.
enum ScrollbackTrimmer {
    static let reset = "\u{1B}[0m"

    static func lastLines(_ text: String, count: Int) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        while lines.last?.isEmpty == true { lines.removeLast() }
        return reset + lines.suffix(count).joined(separator: "\n")
    }
}
