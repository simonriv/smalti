/// Outside text (directories, branches, names) made safe for a zsh prompt value (spec F5, "Escapado"): `%` doubled so
/// prompt expansion shows it, line breaks and tabs replaced, other control characters dropped, and long text trimmed
/// from the left so a channel message stays under 2000 bytes.
public enum ZshEscaping {
    static let maximumLength = 160
    private static let ellipsis = "…"

    public static func literal(_ text: String) -> String {
        trimmed(text).unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar {
            case "%": result += "%%"
            case "\n": result += "␤"
            case "\t": result += " "
            default:
                if !scalar.properties.generalCategory.isControl { result.unicodeScalars.append(scalar) }
            }
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.count > maximumLength ? ellipsis + String(text.suffix(maximumLength - 1)) : text
    }
}

extension Unicode.GeneralCategory {
    fileprivate var isControl: Bool { self == .control || self == .format }
}
