/// Outside text (directories, branches, names) made safe for a zsh prompt value (spec F5, "Escapado"): `psvar` shows
/// it as it is, so only line breaks and tabs are replaced, other control characters dropped, and long text trimmed
/// from the left to `maximumBytes` of UTF-8, whole characters only, so the worst `prompt` answer still fits
/// `InputProtocol.maximumAnswerBytes` (block 2 review, I3).
public enum ZshEscaping {
    public static let maximumBytes = 120
    private static let ellipsis = "…"

    public static func literal(_ text: String) -> String {
        let escaped = text.map(escape)
        guard escaped.reduce(0, { $0 + $1.utf8.count }) > maximumBytes else { return escaped.joined() }
        var budget = maximumBytes - ellipsis.utf8.count
        var kept: [String] = []
        for piece in escaped.reversed() {
            guard piece.utf8.count <= budget else { break }
            budget -= piece.utf8.count
            kept.append(piece)
        }
        return ellipsis + kept.reversed().joined()
    }

    /// One character escaped on its own, so trimming never splits a grapheme.
    private static func escape(_ character: Character) -> String {
        switch character {
        case "\n", "\r", "\r\n", "\u{2028}", "\u{2029}": return "␤"
        case "\t": return " "
        default:
            return character.unicodeScalars.allSatisfy { $0.properties.generalCategory.isControl }
                ? "" : String(character)
        }
    }
}

extension Unicode.GeneralCategory {
    fileprivate var isControl: Bool { self == .control || self == .format }
}
